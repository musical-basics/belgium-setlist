import Foundation
import AppKit

/// Top-level entry point of the lighting module and the ONLY type the host app touches.
///
/// The host hands it a `ShowClock` (read-only view of audio playback) and the show-root folder,
/// and forwards two transport events: `pieceDidStart(order:)` and `allStop()`. Everything else —
/// config, profiles, the rig, the sACN sender, the 40 fps renderer, and the Lighting window — is
/// owned here and never reaches back into the host. If lighting is disabled or fails to start, the
/// host simply gets `nil` and carries on; the sound code is never affected.
public final class LightingController {
    public let config: LightingConfig
    private let showRoot: URL
    private let rig: Rig
    private let sender: SACNSender
    private let renderer: Renderer
    private let log: (String) -> Void
    private var window: LightingWindowController?
    private var visualizer: LightingVisualizerWindowController?

    /// Create the controller. Returns `nil` when lighting is disabled in lighting.json, so the
    /// caller can treat "no lighting" and "lighting failed" identically and never block the show.
    public init?(clock: ShowClock, showRoot: URL, log: @escaping (String) -> Void = { _ in }) {
        self.showRoot = showRoot
        self.log = log

        let cfg = LightingConfigLoader.load(showRoot: showRoot, onWarn: log)
        guard cfg.enabled else {
            log("Lighting is disabled in \(LightingConfigLoader.fileName) — not starting.")
            return nil
        }
        self.config = cfg

        let registry = ProfileRegistry.standard()
        self.rig = Rig(config: cfg, registry: registry, onWarn: log)
        self.sender = SACNSender(
            mode: cfg.network.mode == .unicast ? .unicast : .multicast,
            unicastHost: cfg.network.unicastHost,
            interfaceIP: nil,
            port: cfg.network.port,
            cid: cfg.network.cid,
            sourceName: cfg.network.sourceName,
            onLog: log)
        self.renderer = Renderer(rig: rig, sender: sender, clock: clock,
                                 frameRateHz: cfg.frameRateHz, onLog: log)

        logConfirmChecklist()
    }

    // MARK: Lifecycle

    /// Start the render loop and open the Lighting window. Safe to call once after init.
    public func start() {
        renderer.start()
        let win = LightingWindowController(delegate: self,
                                           confirmChecklist: confirmChecklistText(),
                                           proofFixtureName: defaultProofFixture())
        win.show()
        window = win

        // Abstract stage preview — reads the engine's per-frame snapshot read-only (capture the
        // renderer, not self, so there's no controller↔window retain cycle).
        let renderer = self.renderer
        let viz = LightingVisualizerWindowController(snapshot: { renderer.currentVisual() },
                                                     status: { renderer.currentStatus() })
        viz.show()
        visualizer = viz

        log("Lighting + stage-preview windows opened. \(rig.fixtures.count) fixtures, universes \(rig.universeFrames().map { $0.number }).")
    }

    /// Tear down cleanly (on app quit): stop the renderer (sends sACN termination), close the window.
    public func shutdown() {
        renderer.stop()
        window?.close()
        window = nil
        visualizer?.close()
        visualizer = nil
        // Give the termination packets a moment to leave before the socket goes away.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [sender] in sender.closeSocket() }
    }

    // MARK: Transport events from the host (fail-safe — never throw back to the show)

    /// A piece was fired. Select that piece's lighting program (timecode for EDM, cues for SOLO/TRIO).
    public func pieceDidStart(order: String) {
        guard let pc = config.pieces[order] else {
            log("Lighting: no program configured for piece \(order) — holding current look.")
            renderer.clearProgram()
            return
        }
        switch pc.template {
        case .edm:
            if let file = pc.timeline {
                let url = showRoot.appendingPathComponent(file)
                if let tl = Timeline.load(from: url, onWarn: log) {
                    renderer.loadTimeline(tl, pieceOrder: order)
                    return
                }
                log("Lighting: EDM timeline '\(file)' for piece \(order) is missing/invalid — using a neutral wash.")
            } else {
                log("Lighting: EDM piece \(order) has no timeline configured — using a neutral wash.")
            }
            renderer.loadCues(neutralWash(order))
        case .solo:
            renderer.loadCues(SoloTemplate.build(piece: order,
                                                 cyc: pc.cycColor ?? [0.10, 0.10, 0.45],
                                                 intensity: pc.intensity ?? 0.85))
        case .trio:
            renderer.loadCues(TrioTemplate.build(piece: order,
                                                 cyc: pc.cycColor ?? [0.50, 0.30, 0.10],
                                                 intensity: pc.intensity ?? 0.90))
        case .off:
            renderer.clearProgram()
        }
    }

    /// The show was stopped / panicked from the audio operator (Esc / STOP). Instantly KILL all
    /// lighting output — matching the audio engine's instant stop — so the person at the keyboard
    /// always has a hard kill for a misbehaving mover or strobe. The latch clears automatically on
    /// the next GO (see Renderer.loadTimeline/loadCues). The Lighting window's BLACKOUT button is
    /// the same instant latch; `fadeToBlack` remains available for a graceful out if ever wanted.
    public func allStop() {
        renderer.setBlackout(true)
    }

    // MARK: Helpers

    /// A safe neutral wash so an EDM piece is never accidentally dark if its timeline is missing.
    private func neutralWash(_ order: String) -> CueList {
        var front = FixtureState(); front.intensity = 0.6
        var wash = FixtureState()
        wash.red = 1.0; wash.green = 0.8; wash.blue = 0.6; wash.white = 0.5; wash.intensity = 0.8
        wash.tilt = 0.4; wash.zoom = 0.6
        let cyc = FixtureState.rgb(0.15, 0.10, 0.35, intensity: 0.5)
        var parked = FixtureState(); parked.intensity = 0; parked.pan = 0.5; parked.tilt = 0.55
        return CueList(piece: order, cues: [
            Cue(label: "NEUTRAL WASH (no timeline)", fadeSeconds: 2.0,
                states: ["Front": front, "T1s": wash, "Dalis": cyc, "Spiiders": parked]),
        ])
    }

    /// Proof-of-life target: the first fixture that can emit without arming (a Dalis — its Mode 2
    /// map is live), falling back to the first fixture in the patch.
    private func defaultProofFixture() -> String {
        rig.fixtures.first(where: { !$0.profile.isProvisional && $0.profile.id != "front_wash" })?.name
            ?? (rig.fixtures.first?.name ?? "Dalis4")
    }

    private func logConfirmChecklist() {
        for line in confirmChecklistLines() { log("Lighting CONFIRM ▸ " + line) }
    }

    private func confirmChecklistLines() -> [String] {
        var lines: [String] = []
        lines.append("sACN universes: " + config.universes.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))
        lines.append("Network: \(config.network.mode == .unicast ? "unicast → \(config.network.unicastHost)" : "multicast (239.255.x.x)"), port \(config.network.port)")
        let prov = rig.fixtures.filter { $0.profile.isProvisional }.map { $0.name }
        if !prov.isEmpty {
            lines.append("PROVISIONAL profiles (dark until armed + mode confirmed on the rig): \(prov.joined(separator: ", "))")
        }
        lines.append("Patch is the FINAL venue plot (Lighting_Plot/Lions patchv01.pdf): Spiider Mode 3 33ch, T1 Mode 3 53ch (universe 2); Dalis MKII Mode 2 22ch (universe 3); front catwalk dimmers 2–24 (universe 1).")
        lines.append("On the day: confirm each fixture's PATCHED mode matches the plot, then ARM MOVERS (Spiiders + T1s).")
        return lines
    }

    private func confirmChecklistText() -> String { confirmChecklistLines().joined(separator: "\n") }
}

// MARK: - Window delegate

extension LightingController: LightingWindowDelegate {
    public func lightingToggleBlackout() { renderer.toggleBlackout() }
    public func lightingToggleHold() { renderer.toggleHold() }
    public func lightingAdvanceCue() { renderer.advanceCue() }
    public func lightingPreviousCue() { renderer.previousCue() }
    public func lightingProofOfLife(fixture: String) { renderer.startProofOfLife(fixture: fixture) }
    public func lightingSetArmProvisional(_ armed: Bool) { renderer.setArmProvisional(armed) }
    public func lightingStatus() -> LightingStatus { renderer.currentStatus() }
    public func lightingShowPreview() { visualizer?.show() }
}
