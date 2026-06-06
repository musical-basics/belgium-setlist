import Foundation
import AppKit

/// Headless 60-second self-test: confirms config loads, the audio device is present with
/// >= 4 outputs, every title card exists, and every EDM piece's backing + click load, are
/// (near) equal length, and resample cleanly. Returns a process exit code (0 = pass).
enum SelfTest {
    static func run(configPath: String?) -> Int32 {
        var failures = 0
        func ok(_ s: String)   { print("  ✅ \(s)") }
        func fail(_ s: String) { print("  ❌ \(s)"); failures += 1 }
        func warn(_ s: String) { print("  ⚠️  \(s)") }

        print("ShowRunner self-test")
        print(String(repeating: "=", count: 60))

        let config: ShowConfig
        let root: URL
        do {
            let loaded = try ConfigLoader.load(explicit: configPath)
            config = loaded.config
            root = loaded.root
            ok("Config loaded: \(root.path) (\(config.pieces.count) pieces)")
        } catch {
            fail("Config: \(error)")
            return 1
        }

        // --- Audio device ---
        print("\nAudio device")
        let engine = AudioEngine()
        let rate = config.engineSampleRate ?? 48000
        if let dev = AudioEngine.findDevice(named: config.audioDeviceName) {
            if dev.name.localizedCaseInsensitiveContains(config.audioDeviceName) {
                ok("Found '\(dev.name)' with \(dev.outputChannels) output channels")
            } else {
                warn("'\(config.audioDeviceName)' not found; using fallback '\(dev.name)' (\(dev.outputChannels)ch)")
            }
            if dev.outputChannels >= 4 {
                ok("Device exposes >= 4 outputs → backing 1·2, click 3·4")
            } else {
                fail("Device has only \(dev.outputChannels) outputs — click cannot route to 3·4")
            }
            if engine.configure(device: dev, requestedRate: rate) {
                ok("Audio unit built @ \(Int(engine.sampleRate)) Hz")
            } else {
                fail("Could not build audio unit on '\(dev.name)'")
            }
        } else {
            fail("No audio output device found at all")
        }

        // --- Pieces ---
        print("\nTitle cards & audio")
        var edmCount = 0
        for p in config.pieces {
            let folder = root.appendingPathComponent(p.folder, isDirectory: true)
            let card = folder.appendingPathComponent(p.titleCard)
            if FileManager.default.fileExists(atPath: card.path) {
                ok("[\(p.order)] \(p.title): title card OK")
            } else {
                fail("[\(p.order)] \(p.title): MISSING title card at \(card.path)")
            }
            guard p.hasAudio else { continue }
            edmCount += 1
            guard let bName = p.backing, let cName = p.click else {
                fail("[\(p.order)] hasAudio but backing/click not set in config"); continue
            }
            let bURL = folder.appendingPathComponent(bName)
            let cURL = folder.appendingPathComponent(cName)
            guard FileManager.default.fileExists(atPath: bURL.path) else { fail("[\(p.order)] backing missing: \(bURL.path)"); continue }
            guard FileManager.default.fileExists(atPath: cURL.path) else { fail("[\(p.order)] click missing: \(cURL.path)"); continue }
            do {
                let r = try engine.loadPremix(backingURL: bURL, clickURL: cURL)
                let drift = abs(r.backingFrames - r.clickFrames)
                let driftMs = Double(drift) / r.targetRate * 1000.0
                let line = "[\(p.order)] \(p.title): backing \(r.backingFrames)f (\(Int(r.backingNativeRate))Hz) · click \(r.clickFrames)f (\(Int(r.clickNativeRate))Hz) → \(Int(r.targetRate))Hz"
                if drift == 0 {
                    ok("\(line) — lengths identical")
                } else if driftMs <= 100 {
                    warn("\(line) — differ by \(drift)f (\(String(format: "%.1f", driftMs))ms, padded; start stays locked)")
                } else {
                    warn("\(line) — differ by \(drift)f (\(String(format: "%.0f", driftMs))ms) — check this pair")
                }
                let bc = config.backingChannels ?? [1, 2]
                let cc = config.clickChannels ?? [3, 4]
                if r.premix.frameCount > 0 { ok("  → routed: backing L/R → outs \(bc.map(String.init).joined(separator: "·")), click L/R → outs \(cc.map(String.init).joined(separator: "·"))") }
                else { fail("[\(p.order)] premix is empty") }
            } catch {
                fail("[\(p.order)] load/resample failed: \(error)")
            }
        }

        print("\n" + String(repeating: "=", count: 60))
        print("EDM pieces tested: \(edmCount)   Failures: \(failures)")
        print(failures == 0 ? "RESULT: PASS ✅" : "RESULT: FAIL ❌ (\(failures))")
        print("Log: \(Logger.shared.logURL.path)")
        Logger.shared.info("Self-test complete: \(failures == 0 ? "PASS" : "FAIL (\(failures))")")
        Logger.shared.flush()
        return failures == 0 ? 0 : 1
    }
}
