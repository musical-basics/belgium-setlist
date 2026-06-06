import Foundation

/// Public, thread-safe snapshot of the renderer for the Lighting window.
public struct LightingStatus {
    public var sending = false
    public var blackout = false
    public var hold = false
    public var armProvisional = false
    public var hasProvisional = false
    public var pieceOrder: String?
    public var mode = "idle"            // idle | timecode | cue | proof
    public var position = 0.0
    public var cueLabel: String?
    public var cueIndex = 0
    public var cueCount = 0
    public var universes: [Int] = []
    public var proofActive = false
}

/// What one fixture is doing this frame, for the abstract stage preview. `state` is the INTENDED
/// look (so colour/scale can be verified even before the provisional movers are armed); `emitting`
/// is false when the fixture would NOT actually output live (blackout, or a provisional profile
/// that hasn't been armed) so the preview can flag it.
public struct FixtureVisual {
    public let name: String
    public let kind: String        // profile id: "fargo_9ch" | "spiider_mode2" | "dalis_stub"
    public let address: Int
    public let universe: Int
    public let isProvisional: Bool
    public let emitting: Bool
    public let state: FixtureState
}

/// The lighting renderer: a fixed-rate loop that, every frame, reads the show clock, computes the
/// full lighting state for that instant, writes DMX into the universe frames, and transmits sACN.
///
/// It runs on its OWN serial, high-priority dispatch queue — never the main thread and never the
/// audio render thread — so a slow frame or a socket hiccup cannot stall the UI or glitch audio.
/// Reading the show clock is a lock-free read of a plain value the audio engine already publishes.
///
/// For the EDM pieces, lighting is a pure function of playback position (timecode mode). For the
/// quiet SOLO/TRIO pieces there is no audio clock, so it runs in cue mode: the operator advances
/// crossfaded cues by hand. A global blackout and a manual hold are always available as safety nets.
public final class Renderer {
    private let rig: Rig
    private let sender: SACNSender
    private let clock: ShowClock
    private let frameInterval: Double
    private let onLog: (String) -> Void

    private let queue = DispatchQueue(label: "com.lionelyu.lighting.render", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var running = false

    // ---- queue-confined state (mutated only on `queue`) ----
    private enum Program { case none, timeline(Timeline), cues(CueList) }
    private var program: Program = .none
    private var pieceOrder: String?

    private var blackout = false
    private var hold = false
    private var heldPosition = 0.0

    /// The live look (per fixture). Used for tracking and as the source of cue crossfades.
    private var liveMap: [String: FixtureState] = [:]

    // cue crossfade
    private var cues: [Cue] = []
    private var cueIndex = -1
    private var fadeFrom: [String: FixtureState] = [:]
    private var fadeTo: [String: FixtureState] = [:]
    private var fadeStart = 0.0
    private var fadeDur = 0.0

    // proof of life
    private struct Proof { let fixture: String; let start: Double }
    private var proof: Proof?
    private var proofPriorBlackout = false   // restore the operator's blackout latch after proof
    private let proofRampUp = 1.5, proofHold = 1.0, proofRampDown = 1.5

    // status + visual snapshots (lock-protected for the UI)
    private let statusLock = NSLock()
    private var _status = LightingStatus()
    private var _visual: [FixtureVisual] = []

    public init(rig: Rig, sender: SACNSender, clock: ShowClock, frameRateHz: Double,
                onLog: @escaping (String) -> Void = { _ in }) {
        self.rig = rig
        self.sender = sender
        self.clock = clock
        self.frameInterval = 1.0 / max(1.0, min(60.0, frameRateHz))
        self.onLog = onLog
    }

    // MARK: Lifecycle

    public func start() {
        queue.async { [weak self] in
            guard let self = self, !self.running else { return }
            self.running = true
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now(), repeating: self.frameInterval, leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.tick() }
            self.timer = t
            t.resume()
            self.onLog("Lighting renderer started at \(Int(1.0 / self.frameInterval)) fps.")
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.timer?.cancel(); self.timer = nil
            self.running = false
            // Politely release the universes per E1.31 (3 stream-terminated packets each).
            for u in self.rig.universeFrames() { self.sender.sendTermination(universe: u.number) }
            self.onLog("Lighting renderer stopped.")
        }
    }

    // MARK: Public controls (all hop onto the render queue → no data races)

    public func loadTimeline(_ tl: Timeline, pieceOrder: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.program = .timeline(tl)
            self.pieceOrder = pieceOrder
            self.proof = nil
            self.hold = false
            self.blackout = false   // firing a new piece brings the rig up (clears any STOP/manual blackout)
            self.liveMap = [:]
            self.onLog("Lighting: timecode program for piece \(pieceOrder) (\(tl.tracks.count) tracks).")
        }
    }

    public func loadCues(_ list: CueList) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.program = .cues(list)
            self.cues = list.cues
            self.pieceOrder = list.piece
            self.proof = nil
            self.hold = false
            self.blackout = false   // firing a new piece brings the rig up (clears any STOP/manual blackout)
            self.cueIndex = -1
            self.liveMap = [:]
            self.onLog("Lighting: cue program for piece \(list.piece) (\(list.cues.count) cues).")
            self.gotoCueLocked(0)   // bring up the first cue
        }
    }

    public func clearProgram() {
        queue.async { [weak self] in
            self?.program = .none
            self?.pieceOrder = nil
            self?.proof = nil
        }
    }

    /// Gracefully fade the whole rig to black over `seconds` (used on show STOP). Distinct from the
    /// instant blackout latch — this is a soft out, then the rig holds dark until the next piece.
    public func fadeToBlack(_ seconds: Double = 1.0) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.proof = nil
            self.hold = false
            let cue = Cue(label: "Blackout", fadeSeconds: max(0, seconds), states: ["All": .blackout()])
            self.program = .cues(CueList(piece: self.pieceOrder ?? "", cues: [cue]))
            self.cues = [cue]
            self.cueIndex = -1
            self.gotoCueLocked(0)
        }
    }

    public func setBlackout(_ on: Bool) {
        queue.async { [weak self] in self?.blackout = on; self?.onLog("Lighting: blackout \(on ? "ON" : "off").") }
    }
    public func toggleBlackout() { queue.async { [weak self] in self?.blackout.toggle() } }

    public func setHold(_ on: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.hold = on
            if on { self.heldPosition = self.clock.positionSeconds }
            self.onLog("Lighting: manual hold \(on ? "ON" : "off").")
        }
    }
    public func toggleHold() { queue.async { [weak self] in self?.setHoldLocked(!(self?.hold ?? false)) } }
    private func setHoldLocked(_ on: Bool) { hold = on; if on { heldPosition = clock.positionSeconds } }

    public func advanceCue() { queue.async { [weak self] in guard let s = self else { return }; s.gotoCueLocked(s.cueIndex + 1) } }
    public func previousCue() { queue.async { [weak self] in guard let s = self else { return }; s.gotoCueLocked(s.cueIndex - 1) } }

    public func setArmProvisional(_ armed: Bool) {
        queue.async { [weak self] in
            self?.rig.armProvisional = armed
            self?.onLog("Lighting: provisional fixtures (Spiider/Dalis) \(armed ? "ARMED" : "disarmed").")
        }
    }

    /// Proof of life: drive one fixture to full white, then fade it. The first soundcheck test.
    public func startProofOfLife(fixture: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.proofPriorBlackout = self.blackout   // remember, so proof can shine through a blackout
            self.blackout = false
            self.proof = Proof(fixture: fixture, start: self.now())
            self.onLog("Lighting: PROOF OF LIFE on \(fixture) — full white, then fade.")
        }
    }

    public func currentStatus() -> LightingStatus {
        statusLock.lock(); defer { statusLock.unlock() }
        return _status
    }

    public func currentVisual() -> [FixtureVisual] {
        statusLock.lock(); defer { statusLock.unlock() }
        return _visual
    }

    // MARK: Frame

    private func tick() {
        let map = computeFrame()
        rig.render(map)
        for u in rig.universeFrames() {
            sender.send(universe: u.number, slots: u.slots)
        }
        publishStatus()
        publishVisual(map)
    }

    /// Publish the intended per-fixture look for the stage preview (lock-protected, read on the UI).
    private func publishVisual(_ map: [String: FixtureState]) {
        var vis: [FixtureVisual] = []
        vis.reserveCapacity(rig.fixtures.count)
        for f in rig.fixtures {
            let gatedDark = (f.profile.isProvisional && !rig.armProvisional)
            vis.append(FixtureVisual(
                name: f.name,
                kind: f.profile.id,
                address: f.address,
                universe: f.universeNumber,
                isProvisional: f.profile.isProvisional,
                emitting: !blackout && !gatedDark,
                state: map[f.name] ?? FixtureState()))
        }
        statusLock.lock(); _visual = vis; statusLock.unlock()
    }

    /// Compute the per-fixture state map to output this frame. Empty map => all channels at 0.
    private func computeFrame() -> [String: FixtureState] {
        if blackout { liveMap = [:]; return [:] }

        if let pr = proof { return proofFrame(pr) }

        switch program {
        case .none:
            return liveMap   // hold whatever was last shown

        case .timeline(let tl):
            let pos = hold ? heldPosition : clock.positionSeconds
            var asg: [String: FixtureState] = [:]
            for track in tl.tracks { asg[track.fixture] = track.sample(at: pos) }
            liveMap = applyAudioFlash(to: rig.resolve(asg))
            return liveMap

        case .cues:
            if hold { return liveMap }
            let f = fadeDur > 0 ? min(1, max(0, (now() - fadeStart) / fadeDur)) : 1
            var m: [String: FixtureState] = [:]
            for name in Set(fadeFrom.keys).union(fadeTo.keys) {
                m[name] = FixtureState.lerp(fadeFrom[name] ?? FixtureState(), fadeTo[name] ?? FixtureState(), f)
            }
            liveMap = m
            return liveMap
        }
    }

    /// EDM overlay: preserve the authored timecode look, but push short low-end hits toward white.
    /// The audio engine publishes a bass-weighted fast envelope; this maps it into a visual flash.
    private func applyAudioFlash(to map: [String: FixtureState]) -> [String: FixtureState] {
        guard clock.isRunning else { return map }
        let raw = min(1, max(0, clock.audioFlashLevel))
        guard raw > 0.04 else { return map }

        let hit = Timeline.smoothstep((raw - 0.04) / 0.96)
        var out = map
        for f in rig.fixtures {
            var s = out[f.name] ?? FixtureState()
            s.red = max(s.red, hit)
            s.green = max(s.green, hit)
            s.blue = max(s.blue, hit)
            s.white = max(s.white, hit)
            s.intensity = max(s.intensity, 0.25 + 0.75 * hit)
            if hit > 0.55 {
                s.strobe = max(s.strobe, (hit - 0.55) / 0.45)
            }
            out[f.name] = s
        }
        return out
    }

    /// Build the proof-of-life look (white envelope on one fixture). Auto-exits when finished.
    private func proofFrame(_ pr: Proof) -> [String: FixtureState] {
        let t = now() - pr.start
        let total = proofRampUp + proofHold + proofRampDown
        if t >= total {
            proof = nil
            blackout = proofPriorBlackout   // don't silently release the operator's blackout latch
            onLog("Lighting: proof of life complete.")
            return blackout ? [:] : liveMap
        }
        var level: Double
        if t < proofRampUp { level = t / proofRampUp }
        else if t < proofRampUp + proofHold { level = 1 }
        else { level = 1 - (t - proofRampUp - proofHold) / proofRampDown }

        var white = FixtureState()
        white.white = 1; white.red = 1; white.green = 1; white.blue = 1
        white.intensity = max(0, min(1, level))
        return [pr.fixture: white]
    }

    private func gotoCueLocked(_ index: Int) {
        guard case .cues = program, !cues.isEmpty else { return }
        let i = min(max(0, index), cues.count - 1)
        if i == cueIndex { return }   // already here (tapped past either end) — don't re-fire the fade
        let cue = cues[i]
        fadeFrom = liveMap
        fadeTo = liveMap                                   // start from the live look (tracking)
        for (name, st) in rig.resolve(cue.states) { fadeTo[name] = st }   // overlay the cue
        fadeStart = now()
        fadeDur = max(0, cue.fadeSeconds)
        cueIndex = i
        onLog("Lighting: cue \(i + 1)/\(cues.count) “\(cue.label)” (fade \(String(format: "%.1f", cue.fadeSeconds))s).")
    }

    private func publishStatus() {
        var s = LightingStatus()
        s.sending = sender.isOpen && running
        s.blackout = blackout
        s.hold = hold
        s.armProvisional = rig.armProvisional
        s.hasProvisional = rig.hasProvisionalFixtures
        s.pieceOrder = pieceOrder
        s.universes = rig.universeFrames().map { $0.number }
        s.proofActive = (proof != nil)
        if proof != nil { s.mode = "proof" }
        else {
            switch program {
            case .none: s.mode = "idle"
            case .timeline: s.mode = "timecode"; s.position = hold ? heldPosition : clock.positionSeconds
            case .cues:
                s.mode = "cue"; s.cueCount = cues.count; s.cueIndex = cueIndex
                if cueIndex >= 0 && cueIndex < cues.count { s.cueLabel = cues[cueIndex].label }
            }
        }
        statusLock.lock(); _status = s; statusLock.unlock()
    }

    private func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
}
