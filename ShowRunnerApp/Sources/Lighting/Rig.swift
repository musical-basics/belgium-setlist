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

    public init(config: LightingConfig, registry: ProfileRegistry, onWarn: (String) -> Void = { _ in }) {
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
    /// Tokens: an exact fixture name, or a group — "All", "Fargos", "Spiiders", "Dalis".
    public func expand(_ token: String) -> [Fixture] {
        switch token {
        case "All":      return fixtures
        case "Fargos":   return fixtures.filter { $0.profile.id == "fargo_9ch" }
        case "Spiiders": return fixtures.filter { $0.profile.id == "spiider_mode2" }
        case "Dalis":    return fixtures.filter { $0.profile.id == "dalis_stub" }
        default:         return fixtures.filter { $0.name == token }
        }
    }

    /// Specificity for resolving overlapping tokens — broader groups are applied first so a more
    /// specific token wins (e.g. "All" then "Fargos" then "Fargo1").
    private func specificity(_ token: String) -> Int {
        switch token {
        case "All": return 0
        case "Fargos", "Spiiders", "Dalis": return 1
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
