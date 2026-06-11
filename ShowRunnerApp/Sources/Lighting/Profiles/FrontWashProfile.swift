import Foundation

/// The venue's front-catwalk conventionals as ONE logical fixture. The FINAL plot
/// (`Lighting_Plot/Lions patchv01.pdf`) patches 23 × 2 kW Profile/PC dimmers on universe 1,
/// addresses 2…24 — the house front-of-house wash that keeps the pianist lit.
///
/// One semantic parameter (`intensity`) drives all 23 dimmer channels at the same level, like a
/// submaster. There is nothing else to control — they're conventional dimmers, one channel each.
/// Patch this fixture at address 2 so the footprint covers exactly 2…24.
///
/// Not provisional: a wrong level on a conventional dimmer is just light, and the addresses come
/// from the venue's own patch sheet.
public final class FrontWashProfile: FixtureProfile {
    public let id = "front_wash"
    public let label = "Front catwalk 2kW wash (23 dimmers · universe 1)"
    public let channelCount = 23
    public let isProvisional = false

    public init() {}

    public func render(_ s: FixtureState, into u: DMXUniverse, startAddress addr: Int) {
        let level = DMX.byte(s.intensity)
        u.write(startAddress: addr, bytes: [UInt8](repeating: level, count: channelCount))
    }
}
