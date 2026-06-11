import Foundation

/// The physical rig: the fixtures, their profiles, their DMX addresses, and the universe frames
/// they live in. Turns a set of semantic `FixtureState`s (keyed by logical name or group token)
/// into raw DMX in the right universes — the one place that knows the wiring.
public final class Rig {
    public struct Fixture {
        public let name: String
        public let profile: FixtureProfile
        public let universeNumber: Int
        public let address: Int        // 1-based DMX start address
    }

    public let fixtures: [Fixture]
    /// DMX frames keyed by universe number.
    public let universes: [Int: DMXUniverse]
    private let universeOrder: [Int]

    /// When false, fixtures whose profile is PROVISIONAL (Spiider, Dalis) are NOT written —
    /// they stay dark — so the rig never emits un-verified channel data. Flip to true only after
    /// the venue's mode is confirmed and the profile is filled in from the official chart.
    public var armProvisional: Bool = false

    /// The piano "root" + stretch gain this rig is designed around (see `LightingConfig.StageAnchor`).
    /// Applied to mover aim at output time via `applyStageAnchor(_:)`.
    public var stage: LightingConfig.StageAnchor

    public init(config: LightingConfig, registry: ProfileRegistry, onWarn: (String) -> Void = { _ in }) {
        self.stage = config.stage
        var fx: [Fixture] = []
        var uniSet: [Int] = []
        for fc in config.fixtures {
            guard let profile = registry.profile(id: fc.profile) else {
                onWarn("No profile '\(fc.profile)' for fixture \(fc.name); skipping.")
                continue
            }
            if config.universes[fc.universeRole] == nil {
                onWarn("Fixture \(fc.name) uses unknown universe role '\(fc.universeRole)' — defaulting to universe 1. Check lighting.json.")
            }
            let uni = config.universeNumber(forRole: fc.universeRole)
            if !uniSet.contains(uni) { uniSet.append(uni) }
            fx.append(Fixture(name: fc.name, profile: profile, universeNumber: uni, address: fc.address))
        }
        if uniSet.isEmpty { uniSet = [1] }

        // Warn on overlapping fixture footprints within a universe — a classic show-day mis-patch
        // that would otherwise fail silently (last-rendered fixture overwrites the other's channels).
        let byUniverse = Dictionary(grouping: fx, by: { $0.universeNumber })
        for (uni, list) in byUniverse {
            let occupied = list.filter { $0.profile.channelCount > 0 }.sorted { $0.address < $1.address }
            for i in 1..<occupied.count where occupied.count > 1 {
                let prev = occupied[i - 1], cur = occupied[i]
                let prevEnd = prev.address + prev.profile.channelCount - 1
                if cur.address <= prevEnd {
                    onWarn("DMX OVERLAP on universe \(uni): \(prev.name) (\(prev.address)…\(prevEnd)) overlaps \(cur.name) (from \(cur.address)). Re-patch in lighting.json.")
                }
            }
        }

        self.fixtures = fx
        self.universeOrder = uniSet
        var u: [Int: DMXUniverse] = [:]
        for n in uniSet { u[n] = DMXUniverse(number: n) }
        self.universes = u
    }

    /// Universe frames in a stable order (for the sender).
    public func universeFrames() -> [DMXUniverse] { universeOrder.compactMap { universes[$0] } }

    /// Expand a token into the fixtures it addresses.
    /// Tokens: an exact fixture name, a group — "All", "Spiiders", "T1s", "Dalis", "Front" —
    /// or a "+"-joined list of names/groups (e.g. "Spiider1+Spiider3+Spiider5") so a timeline
    /// track can drive several fixtures (a mirrored pair, a side stack) from one keyframe list.
    public func expand(_ token: String) -> [Fixture] {
        if token.contains("+") {
            var out: [Fixture] = []
            for part in token.split(separator: "+") {
                for f in expand(String(part)) where !out.contains(where: { $0.name == f.name }) {
                    out.append(f)
                }
            }
            return out
        }
        switch token {
        case "All":      return fixtures
        case "Spiiders": return fixtures.filter { $0.profile.id == "spiider_mode3" }
        case "T1s":      return fixtures.filter { $0.profile.id == "t1_mode3" }
        case "Dalis":    return fixtures.filter { $0.profile.id == "dalis_mode2" }
        case "Front":    return fixtures.filter { $0.profile.id == "front_wash" }
        default:         return fixtures.filter { $0.name == token }
        }
    }

    /// Specificity for resolving overlapping tokens — broader groups are applied first so a more
    /// specific token wins (e.g. "All" then "Spiiders" then "Spiider1").
    private func specificity(_ token: String) -> Int {
        switch token {
        case "All": return 0
        case "Spiiders", "T1s", "Dalis", "Front": return 1
        default: return 2
        }
    }

    /// Resolve an (unordered) set of token→state assignments into a final per-fixture state map,
    /// applying broader groups before specific names.
    public func resolve(_ assignments: [String: FixtureState]) -> [String: FixtureState] {
        var out: [String: FixtureState] = [:]
        for token in assignments.keys.sorted(by: { specificity($0) < specificity($1) }) {
            guard let state = assignments[token] else { continue }
            for f in expand(token) { out[f.name] = state }
        }
        return out
    }

    /// Re-aim every mover around the piano "root" before output: for each Spiider/T1,
    /// `finalAim = root + (authoredAim − root) × stretch`, clamped to 0…1 (pan about `pianoPan`,
    /// tilt about `pianoTilt`). This is the ONE place the design is parameterised on the piano's
    /// position — both the live renderer and the headless preview pass their per-frame map through
    /// it. `stretch = 1` is the identity (authored looks unchanged); smaller pulls the whole rig
    /// toward the piano (0 = every beam on the piano), larger exaggerates the spread. Colour,
    /// intensity, zoom and the non-mover fixtures (FrontWash, Dalis) are left untouched.
    public func applyStageAnchor(_ states: [String: FixtureState]) -> [String: FixtureState] {
        let s = stage
        if s.stretch == 1.0 && !s.invertTilt { return states }   // identity — skip the work on the default rig
        func anchored(_ v: Double, about root: Double) -> Double {
            min(1, max(0, root + (v - root) * s.stretch))
        }
        var out = states
        for f in fixtures where f.profile.id == "spiider_mode3" || f.profile.id == "t1_mode3" {
            guard var st = out[f.name] else { continue }
            st.pan = anchored(st.pan, about: s.pianoPan)
            var tilt = anchored(st.tilt, about: s.pianoTilt)
            if s.invertTilt { tilt = 1 - tilt }   // rig hangs inverted: flip beam from upstage to the piano up front
            st.tilt = tilt
            out[f.name] = st
        }
        return out
    }

    /// Render a final per-fixture state map into the universe frames. Clears all frames first.
    /// Fixtures with provisional profiles are skipped unless `armProvisional` is true.
    public func render(_ states: [String: FixtureState]) {
        for (_, u) in universes { u.clear() }
        for f in fixtures {
            if f.profile.isProvisional && !armProvisional { continue }
            guard let state = states[f.name] else { continue }
            guard let u = universes[f.universeNumber] else { continue }
            f.profile.render(state, into: u, startAddress: f.address)
        }
    }

    /// True if any fixture in the rig uses a provisional (unconfirmed) profile.
    public var hasProvisionalFixtures: Bool { fixtures.contains { $0.profile.isProvisional } }
}
