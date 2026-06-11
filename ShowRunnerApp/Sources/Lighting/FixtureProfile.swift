import Foundation

/// The semantic state of one fixture, all normalized to 0…1 (or a neutral default).
///
/// Show logic only ever speaks in these terms — "Dalis4.intensity = 0.8", "Spiider1.pan = 0.5".
/// A `FixtureProfile` translates this into the raw DMX channels for the fixture's confirmed mode.
/// This is the layer that makes the CONFIRM values changeable in ONE place: when the venue
/// confirms a different Spiider mode, only that profile's channel map changes — not a single cue.
public struct FixtureState: Equatable {
    /// Master dimmer, 0…1. Profiles with a 16-bit dimmer use the fine channel automatically.
    public var intensity: Double = 0
    /// Additive RGBW colour, each 0…1.
    public var red: Double = 0
    public var green: Double = 0
    public var blue: Double = 0
    public var white: Double = 0
    /// Strobe rate, 0…1 (0 = shutter open / no strobe). Exact DMX sub-ranges live in the profile.
    public var strobe: Double = 0
    /// Pan / tilt, 0…1 with 0.5 = centre. Profiles expose 16-bit movement when the mode has fine channels.
    public var pan: Double = 0.5
    public var tilt: Double = 0.5
    /// Beam zoom, 0…1 (0 = narrow, 1 = wide — direction is normalized in the profile).
    public var zoom: Double = 0.5
    /// Colour-wheel / colour-macro position, 0…1 (kept for fixtures with a colour channel
    /// distinct from RGBW; unused by the current rig). 0 = no macro (RGBW shows through).
    public var colorMacro: Double = 0

    public init() {}

    /// Linear interpolation between two states (per field). Used by the timeline renderer.
    public static func lerp(_ a: FixtureState, _ b: FixtureState, _ f: Double) -> FixtureState {
        let t = min(1.0, max(0.0, f))
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var s = FixtureState()
        s.intensity = mix(a.intensity, b.intensity)
        s.red = mix(a.red, b.red); s.green = mix(a.green, b.green)
        s.blue = mix(a.blue, b.blue); s.white = mix(a.white, b.white)
        s.strobe = mix(a.strobe, b.strobe)
        s.pan = mix(a.pan, b.pan); s.tilt = mix(a.tilt, b.tilt)
        s.zoom = mix(a.zoom, b.zoom)
        s.colorMacro = mix(a.colorMacro, b.colorMacro)
        return s
    }

    // Convenience builders so timelines read cleanly.
    public static func blackout() -> FixtureState { FixtureState() }

    public static func rgb(_ r: Double, _ g: Double, _ b: Double, intensity: Double = 1) -> FixtureState {
        var s = FixtureState(); s.red = r; s.green = g; s.blue = b; s.intensity = intensity; return s
    }
}

/// Translates a `FixtureState` into raw DMX channels for ONE confirmed fixture mode.
///
/// A profile owns exactly one thing: the channel map for its mode. Everything venue-dependent
/// (channel order, channel count, whether the mode exists at all) is captured here so a mode
/// change is a one-file edit.
public protocol FixtureProfile {
    /// Stable identifier used in lighting.json (e.g. "spiider_mode3", "dalis_mode2").
    var id: String { get }
    /// Human label for logs / UI.
    var label: String { get }
    /// DMX channel footprint of this mode.
    var channelCount: Int { get }
    /// True when this map is NOT yet confirmed against the official chart for the venue's mode.
    /// The renderer refuses to trust a provisional profile for live output unless explicitly armed.
    var isProvisional: Bool { get }

    /// Render `state` into `universe` at the fixture's 1-based `startAddress`.
    func render(_ state: FixtureState, into universe: DMXUniverse, startAddress: Int)
}

/// Registry mapping profile ids → profile instances. Built once from config.
public final class ProfileRegistry {
    private var profiles: [String: FixtureProfile] = [:]

    public init(_ list: [FixtureProfile]) {
        for p in list { profiles[p.id] = p }
    }

    public func profile(id: String) -> FixtureProfile? { profiles[id] }

    /// The default set of profiles for this show's rig (the FINAL venue plot in Lighting_Plot/).
    public static func standard() -> ProfileRegistry {
        ProfileRegistry([SpiiderMode3Profile(), T1Mode3Profile(), DalisMode2Profile(), FrontWashProfile()])
    }
}
