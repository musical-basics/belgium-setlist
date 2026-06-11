import Foundation

// MARK: - Resolved config (what the rest of the module uses)

/// Fully-resolved lighting configuration. Every venue-dependent / CONFIRM value lives here,
/// loaded from `lighting.json` and falling back to the brief's provisional rig when absent.
public struct LightingConfig {
    public var enabled: Bool
    public var frameRateHz: Double
    public var network: ResolvedNetwork
    /// sACN universe number per logical role. e.g. ["front": 1, "movers": 2, "dalis": 3]
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
        public let name: String        // logical name, e.g. "Spiider1"
        public let profile: String     // profile id, e.g. "spiider_mode3"
        public let universeRole: String// key into `universes`, e.g. "movers"
        public let address: Int        // 1-based DMX start address
    }

    public struct PieceLightingConfig {
        /// `auto` = a timecoded timeline driven by the renderer's OWN wall clock (loops), so a
        /// live, non-audio piano piece can still move/fade continuously with no audio clock to follow.
        public enum Template: String { case solo, trio, edm, auto, off }
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

    /// The FINAL venue plot (Lighting_Plot/Lions patchv01.pdf) — used when lighting.json is
    /// missing or partial. 17 fixtures, 3 universes, addresses straight from the patch sheet.
    public static func defaults() -> LightingConfig {
        let cid = parseCID(defaultCIDString) ?? [UInt8](repeating: 0, count: 16)
        let network = LightingConfig.ResolvedNetwork(
            mode: .multicast,                 // venue: "default lighting network protocol is sACN"
            unicastHost: "",                  // set when mode == unicast (the node's IP)
            port: 5568,
            sourceName: "ShowRunner Lighting",
            cid: cid)

        // Universe numbers per the venue patch sheet: 1 = front catwalk (+ hazer/house, untouched),
        // 2 = Spiiders + T1s, 3 = Dalis cyc row.
        let universes = ["front": 1, "movers": 2, "dalis": 3]

        let fixtures: [LightingConfig.FixtureConfig] = [
            .init(name: "FrontWash", profile: "front_wash",   universeRole: "front",  address: 2),
            .init(name: "Spiider1",  profile: "spiider_mode3", universeRole: "movers", address: 1),
            .init(name: "Spiider2",  profile: "spiider_mode3", universeRole: "movers", address: 41),
            .init(name: "Spiider3",  profile: "spiider_mode3", universeRole: "movers", address: 81),
            .init(name: "Spiider4",  profile: "spiider_mode3", universeRole: "movers", address: 121),
            .init(name: "Spiider5",  profile: "spiider_mode3", universeRole: "movers", address: 161),
            .init(name: "Spiider6",  profile: "spiider_mode3", universeRole: "movers", address: 201),
            .init(name: "Spiider7",  profile: "spiider_mode3", universeRole: "movers", address: 241),
            .init(name: "Spiider8",  profile: "spiider_mode3", universeRole: "movers", address: 281),
            .init(name: "T1L",       profile: "t1_mode3",      universeRole: "movers", address: 321),
            .init(name: "T1R",       profile: "t1_mode3",      universeRole: "movers", address: 381),
            .init(name: "Dalis4",    profile: "dalis_mode2",   universeRole: "dalis",  address: 67),
            .init(name: "Dalis5",    profile: "dalis_mode2",   universeRole: "dalis",  address: 89),
            .init(name: "Dalis6",    profile: "dalis_mode2",   universeRole: "dalis",  address: 111),
            .init(name: "Dalis7",    profile: "dalis_mode2",   universeRole: "dalis",  address: 133),
            .init(name: "Dalis8",    profile: "dalis_mode2",   universeRole: "dalis",  address: 155),
            .init(name: "Dalis9",    profile: "dalis_mode2",   universeRole: "dalis",  address: 177),
            .init(name: "Dalis10",   profile: "dalis_mode2",   universeRole: "dalis",  address: 199),
        ]

        // Per-piece lighting languages, keyed by the `order` strings of the CURRENT 20-cue
        // running order in showrunner.json (1-3, S1, 4-6, S2, 7-9, S3, 10-12, S4, 13, E1-E3).
        // EDM pieces reference a timeline file; SOLO/TRIO carry a cyc colour + base intensity.
        // S1-S4 are Lionel's speaking cues — warm, calm, movers parked.
        func solo(_ c: [Double], _ i: Double = 0.85) -> LightingConfig.PieceLightingConfig {
            .init(template: .solo, cycColor: c, intensity: i, timeline: nil)
        }
        func trio(_ c: [Double]) -> LightingConfig.PieceLightingConfig {
            .init(template: .trio, cycColor: c, intensity: 0.9, timeline: nil)
        }
        func edm(_ file: String) -> LightingConfig.PieceLightingConfig {
            .init(template: .edm, cycColor: nil, intensity: nil, timeline: file)
        }
        // `auto`: a self-driven (wall-clock, looping) timeline for a live non-audio piece. cycColor
        // is kept as the SOLO fallback colour if the timeline file is ever missing.
        func auto(_ file: String, _ c: [Double], _ i: Double = 0.85) -> LightingConfig.PieceLightingConfig {
            .init(template: .auto, cycColor: c, intensity: i, timeline: file)
        }
        let speech = solo([0.45, 0.30, 0.12], 0.75)   // warm amber, calm
        let pieces: [String: LightingConfig.PieceLightingConfig] = [
            "1":  auto("Timelines/fantaisie.json", [0.10, 0.10, 0.45]),  // Fantaisie-Impromptu — dark moody purple/blue netherworld
            "2":  auto("Timelines/prelude.json", [0.60, 0.05, 0.05]),    // Prelude in G minor — red, warfare, epic
            "3":  auto("Timelines/rollingthunder.json", [0.10, 0.18, 0.55], 0.9), // Rolling Thunder — storm blue/white + flashes
            "S1": speech,
            "4":  auto("Timelines/fightforfreedom.json", [0.90, 0.25, 0.0]), // Fight for Freedom — orange/red, heroic flames
            "5":  auto("Timelines/colorsofthesoul.json", [0.40, 0.70, 0.0]), // Colors of the Soul — kaleidoscope yellow/green
            "6":  edm("Timelines/torrent.json"),  // Torrent Etude (EDM) — REFERENCE piece
            "S2": speech,
            "7A": auto("Timelines/furelise_solo.json", [0.92, 0.18, 0.35]),  // Für Elise SOLO/REG — romantic pink/red (+teal)
            "7B": edm("Timelines/furelise.json"),                            // Für Elise NIGHTMARE — purple/red
            "8":  edm("Timelines/canon.json"),
            "9A": auto("Timelines/moonlight_solo.json", [0.08, 0.14, 0.55]), // Moonlight SOLO/REG — blue dark moonlight
            "9B": edm("Timelines/moonlight.json"),                           // Moonlight NIGHTMARE — dark blue/purple electric
            "S3": speech,
            "10": auto("Timelines/dreamsofaviolin.json", [0.25, 0.10, 0.40], 0.9), // Dreams of a Violin — dreamy magenta/lavender
            "11": auto("Timelines/gallop.json", [0.15, 0.45, 0.30], 0.9),          // Gallop — earthy blue/green canter
            "12": auto("Timelines/beethovenvirus.json", [0.50, 0.10, 0.10], 0.9),  // Beethoven Virus — fiery red/purple/green
            "S4": speech,
            "13": edm("Timelines/fourseasons.json"),
            "E1": auto("Timelines/sunflowers.json", [0.55, 0.40, 0.05]),           // Sunflowers — peaceful gold
            "E2": auto("Timelines/bumblebee.json", [0.20, 0.55, 0.40], 0.9),       // Bumblebee — will-o'-the-wisp whispers
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
