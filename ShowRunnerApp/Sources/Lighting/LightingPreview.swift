import AppKit

/// Headless render of the abstract stage preview to a PNG — used to eyeball a look without the
/// live windows (and handy for docs / remote checking). Computes the intended look for a piece at
/// a given time exactly as the renderer would, then draws the same StageView offscreen.
public enum LightingPreview {
    /// Render piece `pieceOrder` at `seconds` into the track to a PNG. Returns nil on failure.
    public static func renderPNG(showRoot: URL, pieceOrder: String, seconds: Double,
                                 width: Int = 900, height: Int = 540) -> Data? {
        let cfg = LightingConfigLoader.load(showRoot: showRoot)
        let rig = Rig(config: cfg, registry: .standard())

        let map = rig.applyStageAnchor(look(for: pieceOrder, at: seconds, cfg: cfg, rig: rig, showRoot: showRoot))

        // Show the full intended design (emitting: true) so colour + scale read clearly.
        let visuals = rig.fixtures.map { f in
            FixtureVisual(name: f.name, kind: f.profile.id, address: f.address,
                          universe: f.universeNumber, isProvisional: f.profile.isProvisional,
                          emitting: true, state: map[f.name] ?? FixtureState())
        }

        let view = StageView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.update(visuals, LightingStatus())
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// The intended per-fixture look for a piece at a time (mirrors the renderer's selection logic).
    private static func look(for order: String, at seconds: Double,
                             cfg: LightingConfig, rig: Rig, showRoot: URL) -> [String: FixtureState] {
        guard let pc = cfg.pieces[order] else { return [:] }
        switch pc.template {
        case .edm, .auto:   // both are timeline-driven; preview samples the timeline at `seconds`
            if let file = pc.timeline,
               let tl = Timeline.load(from: showRoot.appendingPathComponent(file)) {
                var asg: [String: FixtureState] = [:]
                for t in tl.tracks { asg[t.fixture] = t.sample(at: seconds) }
                return rig.resolve(asg)
            }
            return [:]
        case .solo:
            return cueLook(SoloTemplate.build(piece: order, cyc: pc.cycColor ?? [0.1, 0.1, 0.45],
                                              intensity: pc.intensity ?? 0.85), rig: rig)
        case .trio:
            return cueLook(TrioTemplate.build(piece: order, cyc: pc.cycColor ?? [0.5, 0.3, 0.1],
                                              intensity: pc.intensity ?? 0.9), rig: rig)
        case .off:
            return [:]
        }
    }

    /// Resolve the first (full-up) cue of a cue list into a per-fixture look.
    private static func cueLook(_ list: CueList, rig: Rig) -> [String: FixtureState] {
        guard let cue = list.cues.first else { return [:] }
        return rig.resolve(cue.states)
    }
}
