import Foundation

// MARK: - Resolved config (what the rest of the module uses)

/// Fully-resolved lighting configuration. Every venue-dependent / CONFIRM value lives here,
/// loaded from `lighting.json` and falling back to the brief's provisional rig when absent.
public struct LightingConfig {
    public var enabled: Bool
    public var frameRateHz: Double
    public var network: ResolvedNetwork
    /// sACN universe number per logical role (CONFIRM). e.g. ["spiider": 1, "fargoDalis": 2]
    public var universes: [String: Int]
    public var fixtures: [FixtureConfig]
    /// Per-piece lighting, keyed by the piece `order` string used in showrunner.json.
    public var pieces: [String: PieceLightingConfig]

    public struct ResolvedNetwork {
        public enum Mode: String { case multicast, unicast }
        public var mode: Mode
        public var unicastHost: String
        public var port: UInt16
        public var sourceName: String
        public var cid: [UInt8]   // 16 bytes, stable per source
    }

    public struct FixtureConfig {
        public let name: String        // logical name, e.g. "Fargo1"
        public let profile: String     // profile id, e.g. "fargo_9ch"
        public let universeRole: String// key into `universes`, e.g. "fargoDalis"
        public let address: Int        // 1-based DMX start address
    }

    public struct PieceLightingConfig {
        public enum Template: String { case solo, trio, edm, off }
        public let template: Template
        public let cycColor: [Double]? // [r,g,b] 0…1 for solo/trio
        public let intensity: Double?  // base intensity for solo/trio
        public let timeline: String?   // relative path to an EDM timeline JSON
    }

    /// Resolve a fixture's universe number via its role, defaulting to 1 if the role is missing.
    public func universeNumber(forRole role: String) -> Int { universes[role] ?? 1 }

    /// The set of distinct universe numbers in use (for allocating DMX frames).
    public func activeUniverseNumbers() -> [Int] {
        var seen: [Int] = []
        for f in fixtures {
            let n = universeNumber(forRole: f.universeRole)
            if !seen.contains(n) { seen.append(n) }
        }
        return seen.isEmpty ? [1] : seen
    }
}

// MARK: - On-disk shape (all optional → robust to partial / missing files)

private struct LightingConfigFile: Codable {
    var enabled: Bool?
    var frameRateHz: Double?
    var network: NetworkFile?
    var universes: [String: Int]?
    var fixtures: [FixtureFile]?
    var pieces: [String: PieceFile]?

    struct NetworkFile: Codable {
        var mode: String?
        var unicastHost: String?
        var port: Int?
        var sourceName: String?
        var cid: String?
    }
    struct FixtureFile: Codable {
        var name: String?
        var profile: String?
        var universe: String?   // role key
        var address: Int?
    }
    struct PieceFile: Codable {
        var template: String?
        var cycColor: [Double]?
        var intensity: Double?
        var timeline: String?
    }
}

// MARK: - Loader

public enum LightingConfigLoader {
    /// File name sitting next to showrunner.json in the show root.
    public static let fileName = "lighting.json"

    /// A stable default CID (RFC-4122 UUID) for this single-source show. Override in lighting.json.
    private static let defaultCIDString = "5A6F574D-0000-4000-8000-53484F574C49" // "ShowRunner Lighting"

    /// Load + resolve config from the show root. Any error (missing file, bad JSON) falls back to
    /// the brief's provisional defaults and is reported via `onWarn` — it NEVER throws or crashes,
    /// so a broken lighting.json can never take down the show.
    public static func load(showRoot: URL, onWarn: (String) -> Void = { _ in }) -> LightingConfig {
        let url = showRoot.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            onWarn("No \(fileName) found in \(showRoot.path) — using provisional defaults from the brief.")
            return defaults()
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(LightingConfigFile.self, from: data)
            return resolve(file, onWarn: onWarn)
        } catch {
            onWarn("Failed to parse \(fileName) (\(error)) — using provisional defaults.")
            return defaults()
        }
    }

    private static func resolve(_ f: LightingConfigFile, onWarn: (String) -> Void) -> LightingConfig {
        let d = defaults()

        let modeStr = f.network?.mode ?? d.network.mode.rawValue
        let mode = LightingConfig.ResolvedNetwork.Mode(rawValue: modeStr) ?? .multicast
        let cid = parseCID(f.network?.cid) ?? d.network.cid

        let network = LightingConfig.ResolvedNetwork(
            mode: mode,
            unicastHost: f.network?.unicastHost ?? d.network.unicastHost,
            port: UInt16(f.network?.port ?? Int(d.network.port)),
            sourceName: f.network?.sourceName ?? d.network.sourceName,
            cid: cid)

        let fixtures: [LightingConfig.FixtureConfig]
        if let ff = f.fixtures, !ff.isEmpty {
            fixtures = ff.compactMap { item in
                guard let name = item.name, let profile = item.profile,
                      let role = item.universe, let addr = item.address else {
                    onWarn("Skipping incomplete fixture entry in \(fileName).")
                    return nil
                }
                return LightingConfig.FixtureConfig(name: name, profile: profile, universeRole: role, address: addr)
            }
        } else {
            fixtures = d.fixtures
        }

        var pieces: [String: LightingConfig.PieceLightingConfig] = d.pieces
        if let pf = f.pieces {
            for (order, p) in pf {
                let template = LightingConfig.PieceLightingConfig.Template(rawValue: p.template ?? "off") ?? .off
                pieces[order] = LightingConfig.PieceLightingConfig(
                    template: template, cycColor: p.cycColor, intensity: p.intensity, timeline: p.timeline)
            }
        }

        return LightingConfig(
            enabled: f.enabled ?? d.enabled,
            frameRateHz: f.frameRateHz ?? d.frameRateHz,
            network: network,
            universes: f.universes ?? d.universes,
            fixtures: fixtures,
            pieces: pieces)
    }

    /// Parse a UUID string into 16 bytes; nil if invalid.
    private static func parseCID(_ s: String?) -> [UInt8]? {
        guard let s = s, let uuid = UUID(uuidString: s) else { return nil }
        let b = uuid.uuid
        return [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7, b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
    }

    /// The brief's provisional rig — used when lighting.json is missing or partial.
    /// 8 fixtures, 2 universes. ALL of these are CONFIRM values isolated here + in lighting.json.
    public static func defaults() -> LightingConfig {
        let cid = parseCID(defaultCIDString) ?? [UInt8](repeating: 0, count: 16)
        let network = LightingConfig.ResolvedNetwork(
            mode: .multicast,                 // CONFIRM: network-direct (multicast) vs own node (unicast)
            unicastHost: "",                  // set when mode == unicast (the node's IP)
            port: 5568,
            sourceName: "ShowRunner Lighting",
            cid: cid)

        let universes = ["spiider": 1, "fargoDalis": 2]   // CONFIRM: the two sACN universe numbers

        // Universe 1: two Spiiders.  Universe 2: four Fargos + two Dalis. Addresses per the brief.
        let fixtures: [LightingConfig.FixtureConfig] = [
            .init(name: "Spiider1", profile: "spiider_mode2", universeRole: "spiider",    address: 1),
            .init(name: "Spiider2", profile: "spiider_mode2", universeRole: "spiider",    address: 28),
            .init(name: "Fargo1",   profile: "fargo_9ch",     universeRole: "fargoDalis", address: 1),
            .init(name: "Fargo2",   profile: "fargo_9ch",     universeRole: "fargoDalis", address: 10),
            .init(name: "Fargo3",   profile: "fargo_9ch",     universeRole: "fargoDalis", address: 19),
            .init(name: "Fargo4",   profile: "fargo_9ch",     universeRole: "fargoDalis", address: 28),
            .init(name: "Dalis1",   profile: "dalis_stub",    universeRole: "fargoDalis", address: 40),
            .init(name: "Dalis2",   profile: "dalis_stub",    universeRole: "fargoDalis", address: 60),
        ]

        // Per-piece lighting languages (the 12 pieces collapse into SOLO / TRIO / EDM).
        // EDM pieces reference a timeline file; SOLO/TRIO carry a cyc colour + base intensity.
        func solo(_ c: [Double]) -> LightingConfig.PieceLightingConfig {
            .init(template: .solo, cycColor: c, intensity: 0.85, timeline: nil)
        }
        func trio(_ c: [Double]) -> LightingConfig.PieceLightingConfig {
            .init(template: .trio, cycColor: c, intensity: 0.9, timeline: nil)
        }
        func edm(_ file: String) -> LightingConfig.PieceLightingConfig {
            .init(template: .edm, cycColor: nil, intensity: nil, timeline: file)
        }
        let pieces: [String: LightingConfig.PieceLightingConfig] = [
            "1":  solo([0.10, 0.10, 0.45]),   // Prelude in G minor — deep blue
            "2":  solo([0.35, 0.05, 0.30]),   // Colors of the Soul — magenta
            "3":  trio([0.55, 0.30, 0.08]),   // Gallop (trio) — warm amber
            "4":  edm("Timelines/torrent.json"),  // Torrent Etude (EDM) — REFERENCE piece
            "5":  trio([0.50, 0.10, 0.10]),   // Beethoven Virus (trio) — red
            "6":  edm("Timelines/canon.json"),
            "7":  solo([0.20, 0.35, 0.15]),   // Fight for Freedom — green
            "8":  solo([0.08, 0.20, 0.45]),   // Winter Wind — cold blue
            "9":  edm("Timelines/moonlight.json"),
            "10": solo([0.55, 0.40, 0.05]),   // Sunflowers — gold
            "11": trio([0.25, 0.10, 0.40]),   // Dreams of a Violin (duet) — violet
            "12": edm("Timelines/furelise.json"),
            "E3": edm("Timelines/stilldre.json"),
        ]

        return LightingConfig(
            enabled: true,
            frameRateHz: 40,
            network: network,
            universes: universes,
            fixtures: fixtures,
            pieces: pieces)
    }
}
