import Foundation
import Lighting

/// Adapts the audio engine into the lighting module's read-only `ShowClock`. This is the only
/// connection between the two worlds: lighting *reads* the playback position the audio engine
/// already publishes for its own UI. It never writes anything back, so it cannot affect audio.
final class AudioShowClock: ShowClock {
    private weak var engine: AudioEngine?
    init(engine: AudioEngine) { self.engine = engine }
    var positionSeconds: Double { engine?.elapsedSeconds ?? 0 }
    var isRunning: Bool { engine?.isPlaying ?? false }
    var audioFlashLevel: Double { Double(engine?.bassFlashLevel ?? 0) }
}

/// Fail-safe glue between ShowRunner and the lighting module.
///
/// If lighting is disabled, misconfigured, or unavailable, `controller` is simply `nil` and every
/// method here is a no-op — the audio show runs exactly as it did before lighting existed. The
/// bridge owns the lighting controller so the audio code never holds a lighting type directly.
final class LightingBridge {
    private let clock: AudioShowClock
    private let controller: LightingController?

    init(engine: AudioEngine, showRoot: URL) {
        let clock = AudioShowClock(engine: engine)
        self.clock = clock
        self.controller = LightingController(
            clock: clock,
            showRoot: showRoot,
            log: { Logger.shared.info("[Lighting] " + $0) })
        if controller == nil {
            Logger.shared.info("[Lighting] inactive (disabled in lighting.json or unavailable).")
        }
    }

    /// Open the lighting window and start the 40 fps renderer.
    func start() { controller?.start() }

    /// True when the lighting module is live (config enabled). The operator window uses this to
    /// enable/disable its lighting "show window" buttons.
    var isActive: Bool { controller != nil }

    /// Re-show the lighting windows from the operator window (e.g. if they were closed). No-ops when off.
    func showLightingWindow() { controller?.showLightingWindow() }
    func showPreviewWindow() { controller?.showPreviewWindow() }

    // MARK: Phone-remote lighting controls (mirror the Lighting window's ARM MOVERS button)

    /// Whether there are provisional movers (Spiiders/T1s) that can be armed. False when lighting is off.
    var moversArmable: Bool { controller?.lightingStatus().hasProvisional ?? false }
    /// Whether the provisional movers are currently armed.
    var moversArmed: Bool { controller?.lightingStatus().armProvisional ?? false }
    /// Toggle the provisional movers on/off — exactly like the Lighting window's ARM MOVERS button.
    func toggleArmMovers() {
        guard let c = controller else { return }
        c.lightingSetArmProvisional(!c.lightingStatus().armProvisional)
    }

    /// A piece was fired — pick its lighting program (timecode for EDM, cues for SOLO/TRIO).
    func pieceDidStart(order: String) { controller?.pieceDidStart(order: order) }

    /// Show stopped / panicked — softly fade lighting to black.
    func stop() { controller?.allStop() }

    /// App is quitting — stop sending sACN and close the lighting window.
    func shutdown() { controller?.shutdown() }
}
