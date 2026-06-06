import Foundation
import AVFoundation
import AudioToolbox
import CoreAudio

// MARK: - Pre-mixed audio buffer

/// A piece's audio pre-mixed into 4 separate Float32 channel buffers, all at the engine rate:
///   ch[0] = backing L  -> device out 1
///   ch[1] = backing R  -> device out 2
///   ch[2] = click  L   -> device out 3
///   ch[3] = click  R   -> device out 4
/// Sample-lock is guaranteed by construction: one buffer, one shared play head.
final class PremixedAudio {
    let frameCount: Int
    let sampleRate: Double
    let channels: [UnsafeMutablePointer<Float>]   // exactly 4

    init(frameCount: Int, sampleRate: Double) {
        let cap = max(1, frameCount)
        self.frameCount = frameCount
        self.sampleRate = sampleRate
        self.channels = (0..<4).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: cap)
            p.initialize(repeating: 0, count: cap)
            return p
        }
    }

    deinit {
        let cap = max(1, frameCount)
        for c in channels { c.deinitialize(count: cap); c.deallocate() }
    }
}

// MARK: - Render state shared with the real-time callback

/// Plain-old-data shared between the main thread and the audio render thread.
/// Mutated ONLY while the audio unit is stopped (stop-mutate-start), so no locks/atomics
/// are required. `currentFrame` is written by the audio thread and read (possibly slightly
/// stale, which is fine) by the main thread for the elapsed-time display.
struct RenderState {
    var ch0: UnsafeMutablePointer<Float>?
    var ch1: UnsafeMutablePointer<Float>?
    var ch2: UnsafeMutablePointer<Float>?
    var ch3: UnsafeMutablePointer<Float>?
    var frameCount: Int = 0
    var currentFrame: Int = 0
    var playing: Int32 = 0   // 0 = silence, 1 = playing
    // Destination device-output channel (0-based) for each source: backing L/R, click L/R.
    var dest0: Int = 0   // backing L
    var dest1: Int = 1   // backing R
    var dest2: Int = 2   // click L
    var dest3: Int = 3   // click R
    // Effective linear gains (master × per-piece) applied in the callback.
    var gainBacking: Float = 1
    var gainClick: Float = 1
    // Per-channel peak of the most recent render block (0…1), for the UI level meters.
    var peak0: Float = 0
    var peak1: Float = 0
    var peak2: Float = 0
    var peak3: Float = 0
}

/// Mix `n` frames of `src` (starting at `pos`) into device output channel `destCh`, scaled by
/// `gain`, and return the post-gain block peak. RT-safe: no allocation, no ARC. Assumes all device
/// buffers were pre-zeroed. Uses `+=` so that when two sources share a destination channel (the
/// stereo fold-down on a 2-channel device) they SUM rather than overwrite; on the normal 4-channel
/// path each source has its own channel, so `+=` into a zeroed buffer is identical to assignment.
@inline(__always)
private func placeChannel(_ src: UnsafeMutablePointer<Float>?, _ destCh: Int, _ gain: Float,
                          _ abl: UnsafeMutableAudioBufferListPointer,
                          _ pos: Int, _ n: Int) -> Float {
    guard let src = src, n > 0, destCh >= 0, destCh < abl.count,
          let raw = abl[destCh].mData else { return 0 }
    let out = raw.assumingMemoryBound(to: Float.self)
    let base = src + pos
    var pk: Float = 0
    var j = 0
    while j < n {
        let v = base[j] * gain
        out[j] += v
        let a = v < 0 ? -v : v
        if a > pk { pk = a }
        j += 1
    }
    return pk
}

/// The C render callback. No allocation, no ARC, no locks — reads RenderState via a raw pointer.
private let showRunnerRenderProc: AURenderCallback = { (inRefCon, _, _, _, inNumberFrames, ioData) -> OSStatus in
    guard let ioData = ioData else { return noErr }
    let abl = UnsafeMutableAudioBufferListPointer(ioData)
    let frames = Int(inNumberFrames)
    let st = inRefCon.assumingMemoryBound(to: RenderState.self)

    // Always start from pure silence on every device output channel.
    for i in 0..<abl.count {
        if let d = abl[i].mData { memset(d, 0, Int(abl[i].mDataByteSize)) }
    }

    if st.pointee.playing == 0 {
        st.pointee.peak0 = 0; st.pointee.peak1 = 0; st.pointee.peak2 = 0; st.pointee.peak3 = 0
        return noErr
    }

    let total = st.pointee.frameCount
    let pos = st.pointee.currentFrame
    let avail = max(0, total - pos)
    let n = min(frames, avail)

    // Place each source on its configured destination output channel (rest stay silent),
    // scaled by the effective backing/click gain.
    let gB = st.pointee.gainBacking, gC = st.pointee.gainClick
    st.pointee.peak0 = placeChannel(st.pointee.ch0, st.pointee.dest0, gB, abl, pos, n)
    st.pointee.peak1 = placeChannel(st.pointee.ch1, st.pointee.dest1, gB, abl, pos, n)
    st.pointee.peak2 = placeChannel(st.pointee.ch2, st.pointee.dest2, gC, abl, pos, n)
    st.pointee.peak3 = placeChannel(st.pointee.ch3, st.pointee.dest3, gC, abl, pos, n)

    let newPos = pos + n
    st.pointee.currentFrame = min(newPos, total)
    if newPos >= total {
        st.pointee.playing = 0   // reached end -> stop on next cycle
    }
    return noErr
}

/// Fires (on a CoreAudio thread) when the bound device's "is alive" property changes —
/// i.e. the interface was unplugged. Bounces to the main thread to stop + alert.
private let showRunnerDeviceAliveListener: AudioObjectPropertyListenerProc = { (_, _, _, refCon) -> OSStatus in
    guard let refCon = refCon else { return noErr }
    let engine = Unmanaged<AudioEngine>.fromOpaque(refCon).takeUnretainedValue()
    DispatchQueue.main.async { engine.handleDeviceLost() }
    return noErr
}

// MARK: - Audio device descriptor

struct AudioDeviceInfo {
    let id: AudioDeviceID
    let name: String
    let outputChannels: Int
}

// MARK: - Audio engine

final class AudioEngine {
    private(set) var deviceID: AudioDeviceID = 0
    private(set) var deviceName: String = "—"
    private(set) var deviceChannels: Int = 0
    private(set) var sampleRate: Double = 48000
    /// Output routing, 0-based device channels. Defaults: backing 0·1, click 2·3 (outs 1·2 / 3·4).
    private(set) var backingChannels: (Int, Int) = (0, 1)
    private(set) var clickChannels: (Int, Int) = (2, 3)
    /// True when the click is summed onto the backing pair because its own pair doesn't exist on
    /// the current device (e.g. a 2-channel Mac speaker) — everything plays in stereo.
    private(set) var clickFolded = false
    /// True when the click reaches an output at all (always true once a device is configured,
    /// since we fold to stereo when its own pair is missing).
    var clickRouted: Bool { clickChannels.0 < deviceChannels && clickChannels.1 < deviceChannels }

    /// Set output routing (0-based device channels). If the requested click pair doesn't exist on
    /// the current device, the click is FOLDED onto the backing pair so the show still plays in
    /// stereo (backing + click summed to outs 1·2). Updates the live render state.
    func setRouting(backing: (Int, Int), click: (Int, Int)) {
        let maxCh = max(1, deviceChannels)
        let b = (min(max(0, backing.0), maxCh - 1), min(max(0, backing.1), maxCh - 1))
        let c: (Int, Int)
        if click.0 < deviceChannels && click.1 < deviceChannels {
            c = (max(0, click.0), max(0, click.1))
        } else {
            c = b   // click pair doesn't fit → fold onto backing so a stereo device still plays it
        }
        backingChannels = b
        clickChannels = c
        clickFolded = (c.0 == b.0 && c.1 == b.1)
        statePtr.pointee.dest0 = b.0
        statePtr.pointee.dest1 = b.1
        statePtr.pointee.dest2 = c.0
        statePtr.pointee.dest3 = c.1
        if clickFolded {
            Logger.shared.info("Routing: \(deviceChannels)-ch device — backing+click summed to outs \(b.0 + 1)·\(b.1 + 1) (stereo fold).")
        } else {
            Logger.shared.info("Routing: backing → outs \(b.0 + 1)·\(b.1 + 1), click → outs \(c.0 + 1)·\(c.1 + 1).")
        }
    }

    // MARK: Volume / gain

    /// Master fader gains in dB (live-adjustable). -inf at the bottom of the slider range.
    private(set) var masterBackingDb: Double = 0
    private(set) var masterClickDb: Double = 0
    // Per-piece trims (dB) of whatever is currently loaded.
    private var pieceBackingDb: Double = 0
    private var pieceClickDb: Double = 0

    static func dbToLinear(_ db: Double) -> Float {
        if db <= -40 { return 0 }   // bottom of the fader == mute
        return Float(pow(10.0, db / 20.0))
    }

    func setMasterGains(backingDb: Double, clickDb: Double) {
        masterBackingDb = backingDb
        masterClickDb = clickDb
        updateEffectiveGains()
    }

    /// Set the per-piece trim for the currently-loaded piece (live).
    func setPieceTrim(backingDb: Double, clickDb: Double) {
        pieceBackingDb = backingDb
        pieceClickDb = clickDb
        updateEffectiveGains()
    }

    private func updateEffectiveGains() {
        statePtr.pointee.gainBacking = AudioEngine.dbToLinear(masterBackingDb + pieceBackingDb)
        statePtr.pointee.gainClick = AudioEngine.dbToLinear(masterClickDb + pieceClickDb)
    }
    var deviceReady: Bool { audioUnit != nil }

    private var audioUnit: AudioUnit?
    private var statePtr: UnsafeMutablePointer<RenderState>
    private var activePremix: PremixedAudio?   // keep a strong ref while playing
    private var running = false
    private var deviceListenerInstalled = false

    /// Called on the MAIN thread if the selected device disappears mid-show.
    var onDeviceLost: (() -> Void)?

    init() {
        statePtr = UnsafeMutablePointer<RenderState>.allocate(capacity: 1)
        statePtr.initialize(to: RenderState())
    }

    deinit {
        teardownUnit()
        statePtr.deinitialize(count: 1)
        statePtr.deallocate()
    }

    // MARK: Device discovery

    static func outputDevices() -> [AudioDeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        var result: [AudioDeviceInfo] = []
        for id in ids {
            let chans = outputChannelCount(id)
            if chans > 0 {
                result.append(AudioDeviceInfo(id: id, name: deviceName(id), outputChannels: chans))
            }
        }
        return result
    }

    static func deviceName(_ id: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfName)
        if status == noErr, let n = cfName?.takeRetainedValue() {
            return n as String
        }
        return "Device \(id)"
    }

    static func outputChannelCount(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: 0)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        var total = 0
        for b in list { total += Int(b.mNumberChannels) }
        return total
    }

    /// Find a device whose name loosely contains `name`. Falls back to default output device.
    static func findDevice(named name: String) -> AudioDeviceInfo? {
        let devices = outputDevices()
        if let exact = devices.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            return exact
        }
        // fall back to system default output device
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var devID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID) == noErr {
            return devices.first(where: { $0.id == devID })
        }
        return devices.first
    }

    // MARK: Device sample-rate

    @discardableResult
    private static func setDeviceSampleRate(_ id: AudioDeviceID, _ rate: Double) -> Double {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var desired = rate
        _ = AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &desired)
        // Poll until it takes effect (devices change rate asynchronously), up to ~1.5s.
        var current = currentDeviceSampleRate(id)
        var waited = 0
        while abs(current - rate) > 1.0 && waited < 30 {
            usleep(50_000)
            current = currentDeviceSampleRate(id)
            waited += 1
        }
        return current
    }

    private static func currentDeviceSampleRate(_ id: AudioDeviceID) -> Double {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate)
        return rate
    }

    // MARK: Configure / select device

    /// Configure the engine on the given device at the requested rate. Returns true on success.
    @discardableResult
    func configure(device: AudioDeviceInfo, requestedRate: Double) -> Bool {
        teardownUnit()
        deviceID = device.id
        deviceName = device.name
        deviceChannels = max(2, device.outputChannels)

        // Lock the device to a single rate for the whole show.
        let actual = AudioEngine.setDeviceSampleRate(device.id, requestedRate)
        sampleRate = (actual > 0) ? actual : requestedRate
        if abs(sampleRate - requestedRate) > 1.0 {
            Logger.shared.warn("Device '\(device.name)' did not accept \(Int(requestedRate)) Hz; using \(Int(sampleRate)) Hz.")
        }

        do {
            try buildUnit()
            Logger.shared.info("Audio configured: '\(device.name)' \(deviceChannels)ch @ \(Int(sampleRate)) Hz. Click routed: \(clickRouted)")
            return true
        } catch {
            Logger.shared.error("Failed to build audio unit on '\(device.name)': \(error)")
            teardownUnit()
            return false
        }
    }

    private func buildUnit() throws {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw NSError(domain: "ShowRunner", code: -1, userInfo: [NSLocalizedDescriptionKey: "HALOutput component not found"])
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &unit), "AudioComponentInstanceNew")
        guard let u = unit else { throw NSError(domain: "ShowRunner", code: -2) }

        // Bind to the chosen device.
        var dev = deviceID
        try check(AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice,
                                       kAudioUnitScope_Global, 0, &dev,
                                       UInt32(MemoryLayout<AudioDeviceID>.size)),
                  "set CurrentDevice")

        // The format WE supply: Float32, non-interleaved, deviceChannels wide, at the device rate.
        // Channel count matches the device's output channel count, so channel i -> device output i
        // (identity routing) with no ChannelMap ambiguity. We zero the unused channels ourselves.
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = sampleRate
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
        asbd.mFramesPerPacket = 1
        asbd.mChannelsPerFrame = UInt32(deviceChannels)
        asbd.mBitsPerChannel = 32
        asbd.mBytesPerFrame = 4     // non-interleaved: per-channel bytes per frame
        asbd.mBytesPerPacket = 4
        try check(AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat,
                                       kAudioUnitScope_Input, 0, &asbd,
                                       UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
                  "set StreamFormat")

        // Render callback.
        var cb = AURenderCallbackStruct(inputProc: showRunnerRenderProc,
                                        inputProcRefCon: UnsafeMutableRawPointer(statePtr))
        try check(AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback,
                                       kAudioUnitScope_Input, 0, &cb,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
                  "set RenderCallback")

        try check(AudioUnitInitialize(u), "AudioUnitInitialize")
        audioUnit = u

        // Watch for the device being unplugged mid-show.
        var aliveAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectAddPropertyListener(deviceID, &aliveAddr, showRunnerDeviceAliveListener,
                                          Unmanaged.passUnretained(self).toOpaque()) == noErr {
            deviceListenerInstalled = true
        }
    }

    private func teardownUnit() {
        if deviceListenerInstalled, deviceID != 0 {
            var aliveAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListener(deviceID, &aliveAddr, showRunnerDeviceAliveListener,
                                              Unmanaged.passUnretained(self).toOpaque())
            deviceListenerInstalled = false
        }
        if let u = audioUnit {
            if running { AudioOutputUnitStop(u); running = false }
            AudioUnitUninitialize(u)
            AudioComponentInstanceDispose(u)
        }
        audioUnit = nil
        statePtr.pointee.playing = 0
    }

    /// Main-thread handler for device disappearance.
    func handleDeviceLost() {
        Logger.shared.error("Audio device lost (unplugged?): \(deviceName)")
        stop()
        onDeviceLost?()
    }

    // MARK: Transport

    /// Start a pre-mixed buffer. Backing + click begin on the exact same frame (sample-locked).
    func play(_ pre: PremixedAudio, pieceBackingDb: Double, pieceClickDb: Double) {
        guard let u = audioUnit else {
            Logger.shared.warn("play() called with no audio device configured.")
            return
        }
        self.pieceBackingDb = pieceBackingDb
        self.pieceClickDb = pieceClickDb
        updateEffectiveGains()
        // Silence first, THEN stop, so an in-flight render callback (which checks `playing`
        // before touching any buffer pointer) cannot read the pointers we are about to
        // overwrite. AudioOutputUnitStop/Start also act as memory barriers across the audio
        // thread; the explicit OSMemoryBarrier() calls make the ordering unambiguous.
        statePtr.pointee.playing = 0
        OSMemoryBarrier()
        if running { AudioOutputUnitStop(u); running = false }
        statePtr.pointee.ch0 = pre.channels[0]
        statePtr.pointee.ch1 = pre.channels[1]
        statePtr.pointee.ch2 = pre.channels[2]
        statePtr.pointee.ch3 = pre.channels[3]
        statePtr.pointee.frameCount = pre.frameCount
        statePtr.pointee.currentFrame = 0
        activePremix = pre
        OSMemoryBarrier()
        statePtr.pointee.playing = 1
        let status = AudioOutputUnitStart(u)
        if status == noErr { running = true }
        else { Logger.shared.error("AudioOutputUnitStart failed: \(status)") }
    }

    /// Instant stop / panic.
    func stop() {
        statePtr.pointee.playing = 0
        OSMemoryBarrier()
        if let u = audioUnit, running {
            AudioOutputUnitStop(u)
            running = false
        }
        // Now safe to drop the buffer references — the callback only dereferences these
        // pointers when playing == 1, which we cleared above.
        statePtr.pointee.ch0 = nil
        statePtr.pointee.ch1 = nil
        statePtr.pointee.ch2 = nil
        statePtr.pointee.ch3 = nil
        statePtr.pointee.peak0 = 0
        statePtr.pointee.peak1 = 0
        statePtr.pointee.peak2 = 0
        statePtr.pointee.peak3 = 0
        activePremix = nil
    }

    var isPlaying: Bool { statePtr.pointee.playing == 1 }
    /// Current playhead in seconds (read by the UI; may be a tiny bit stale, which is fine).
    var elapsedSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(statePtr.pointee.currentFrame) / sampleRate
    }
    /// Live output peak (0…1) for the meters. Backing = outs 1·2, click = outs 3·4.
    var backingLevel: Float { max(statePtr.pointee.peak0, statePtr.pointee.peak1) }
    var clickLevel: Float { max(statePtr.pointee.peak2, statePtr.pointee.peak3) }

    // MARK: Loading & resampling

    private struct Stereo { var frames: Int; var l: [Float]; var r: [Float] }

    /// Read a WAV to Float32 L/R, resampled to `targetRate`. Handles mono and >2ch gracefully.
    private static func readStereo(_ url: URL, targetRate: Double) throws -> Stereo {
        let file = try AVAudioFile(forReading: url)
        let inFmt = file.processingFormat   // Float32, deinterleaved, file's native rate
        let inFrames = AVAudioFrameCount(file.length)
        guard inFrames > 0 else { return Stereo(frames: 0, l: [], r: []) }
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: inFrames) else {
            throw NSError(domain: "ShowRunner", code: -10, userInfo: [NSLocalizedDescriptionKey: "alloc input buffer"])
        }
        try file.read(into: inBuf)

        let needsResample = abs(inFmt.sampleRate - targetRate) > 0.5
        let working: AVAudioPCMBuffer
        if needsResample {
            guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: targetRate,
                                             channels: inFmt.channelCount,
                                             interleaved: false),
                  let conv = AVAudioConverter(from: inFmt, to: outFmt) else {
                throw NSError(domain: "ShowRunner", code: -11, userInfo: [NSLocalizedDescriptionKey: "create converter"])
            }
            let ratio = targetRate / inFmt.sampleRate
            let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 8192
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outCap) else {
                throw NSError(domain: "ShowRunner", code: -12, userInfo: [NSLocalizedDescriptionKey: "alloc output buffer"])
            }
            var fed = false
            var convErr: NSError?
            let status = conv.convert(to: outBuf, error: &convErr) { _, outStatus in
                if fed { outStatus.pointee = .endOfStream; return nil }
                fed = true
                outStatus.pointee = .haveData
                return inBuf
            }
            if status == .error, let e = convErr { throw e }
            working = outBuf
        } else {
            working = inBuf
        }

        return extractStereo(working)
    }

    private static func extractStereo(_ buf: AVAudioPCMBuffer) -> Stereo {
        let frames = Int(buf.frameLength)
        guard frames > 0, let data = buf.floatChannelData else { return Stereo(frames: 0, l: [], r: []) }
        let ch = Int(buf.format.channelCount)
        var l = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: frames)
        let src0 = data[0]
        let src1 = ch >= 2 ? data[1] : data[0]   // mono -> duplicate
        l.withUnsafeMutableBufferPointer { $0.baseAddress!.update(from: src0, count: frames) }
        r.withUnsafeMutableBufferPointer { $0.baseAddress!.update(from: src1, count: frames) }
        return Stereo(frames: frames, l: l, r: r)
    }

    struct LoadReport {
        var backingFrames: Int
        var clickFrames: Int
        var backingNativeRate: Double
        var clickNativeRate: Double
        var targetRate: Double
        var premix: PremixedAudio
    }

    /// Build a pre-mixed 4-channel buffer for one piece. Backing and click are each resampled
    /// to the engine rate with identical converter configuration, preserving sample-lock.
    func loadPremix(backingURL: URL, clickURL: URL) throws -> LoadReport {
        let rate = sampleRate
        let backingNative = try AVAudioFile(forReading: backingURL).processingFormat.sampleRate
        let clickNative = try AVAudioFile(forReading: clickURL).processingFormat.sampleRate
        let b = try AudioEngine.readStereo(backingURL, targetRate: rate)
        let c = try AudioEngine.readStereo(clickURL, targetRate: rate)
        let frames = max(b.frames, c.frames)
        guard frames > 0 else {
            throw NSError(domain: "ShowRunner", code: -20, userInfo: [NSLocalizedDescriptionKey:
                "Backing and click are both empty (0 frames) — check the WAV files."])
        }
        guard frames <= 3_600 * Int(rate.rounded()) else {   // > 1 hour: refuse rather than trap on a huge allocation
            throw NSError(domain: "ShowRunner", code: -21, userInfo: [NSLocalizedDescriptionKey:
                "Audio longer than 1 hour is not supported (\(frames) frames)."])
        }
        let pre = PremixedAudio(frameCount: frames, sampleRate: rate)
        if b.frames > 0 {
            b.l.withUnsafeBufferPointer { pre.channels[0].update(from: $0.baseAddress!, count: b.frames) }
            b.r.withUnsafeBufferPointer { pre.channels[1].update(from: $0.baseAddress!, count: b.frames) }
        }
        if c.frames > 0 {
            c.l.withUnsafeBufferPointer { pre.channels[2].update(from: $0.baseAddress!, count: c.frames) }
            c.r.withUnsafeBufferPointer { pre.channels[3].update(from: $0.baseAddress!, count: c.frames) }
        }
        return LoadReport(backingFrames: b.frames, clickFrames: c.frames,
                          backingNativeRate: backingNative, clickNativeRate: clickNative,
                          targetRate: rate, premix: pre)
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr {
            throw NSError(domain: "ShowRunner.CoreAudio", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "\(what) failed (OSStatus \(status))"])
        }
    }
}
