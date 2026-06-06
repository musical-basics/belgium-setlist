import Foundation

/// Fargo Stagepar 19 Pro Zoom MKII (RGBW zoom PAR), 9-channel mode.
///
/// CONFIRMED present at the venue: the CC De Factorij technical rider lists "28 × Fargo Stagepar
/// 19 Pro Zoom MKII" — this is a Fargo-brand StagePar (NOT a Robe fixture, which is why a search
/// for a "Robe Fargo" finds nothing). We patch 4 of them.
///
/// Channel order is taken DIRECTLY from the brief (a verified theatre patch using these exact
/// fixtures), 0-based within the fixture footprint:
///
///   0 Red · 1 Green · 2 Blue · 3 White · 4 Dimmer · 5 Dimmer Fine · 6 Strobe · 7 Color · 8 Zoom
///
/// CONFIRM-ON-DAY: re-verify this order against the venue's patch during soundcheck. If it is
/// wrong, change ONLY the offsets in `Ch` below — no cue or timeline changes are needed.
///
/// Assumptions, all flagged CONFIRM and isolated to this file:
///  • The Dimmer channel is a MASTER over RGBW (RGBW are absolute; Dimmer scales the output).
///    So a look must raise BOTH a colour and the dimmer to emit light.
///  • Strobe: 0 = shutter open / no strobe. A positive `strobe` maps into [strobeMin…strobeMax].
///  • Zoom: 0 = narrow beam, 1 = wide. Reverse `zoomReversed` if the fixture is the other way.
///  • Color: a colour-macro channel; 0 = none (RGBW passes through).
public final class FargoProfile: FixtureProfile {
    public let id = "fargo_9ch"
    public let label = "Fargo Stagepar 19 Pro Zoom MKII (9ch)"
    public let channelCount = 9
    /// The Fargo order is brief-confirmed, so this profile is trusted (verify on the day anyway).
    public let isProvisional = false

    /// 0-based channel offsets — the single place to edit if the venue's patch differs.
    private enum Ch {
        static let red = 0, green = 1, blue = 2, white = 3
        static let dimmer = 4, dimmerFine = 5
        static let strobe = 6, color = 7, zoom = 8
    }

    // Strobe DMX window. No Fargo value chart is published; these match the hardware-identical
    // Elation Arena Par Zoom "strobe slow→fast" band (64…95) as the best available proxy — VERIFY
    // by sweeping the channel on the day. `strobe == 0` writes `strobeOpen` (no strobe).
    private let strobeMin: Double = 64
    private let strobeMax: Double = 95
    // Value written when there is no strobe. 0 assumes offset-6 is "0 = open / no strobe" (the
    // common design, and what makes proof-of-life light up). IF the Fargo is DARK during
    // proof-of-life with RGBW + Dimmer up, its offset-6 is a shutter where low = CLOSED — set this
    // to ~32 (open). CONFIRM on the day.
    private let strobeOpen: UInt8 = 0
    private let zoomReversed = false

    public init() {}

    public func render(_ s: FixtureState, into u: DMXUniverse, startAddress addr: Int) {
        guard channelCount > 0 else { return }
        var bytes = [UInt8](repeating: 0, count: channelCount)

        bytes[Ch.red]   = DMX.byte(s.red)
        bytes[Ch.green] = DMX.byte(s.green)
        bytes[Ch.blue]  = DMX.byte(s.blue)
        bytes[Ch.white] = DMX.byte(s.white)

        let (dCoarse, dFine) = DMX.word(s.intensity)
        bytes[Ch.dimmer] = dCoarse
        bytes[Ch.dimmerFine] = dFine

        bytes[Ch.strobe] = strobeByte(s.strobe)
        bytes[Ch.color]  = DMX.byte(s.colorMacro)
        let z = zoomReversed ? (1 - s.zoom) : s.zoom
        bytes[Ch.zoom]   = DMX.byte(z)

        u.write(startAddress: addr, bytes: bytes)
    }

    private func strobeByte(_ strobe: Double) -> UInt8 {
        guard strobe > 0.001 else { return strobeOpen }   // no strobe
        let v = strobeMin + (strobeMax - strobeMin) * min(1, max(0, strobe))
        return UInt8(v.rounded())
    }
}
