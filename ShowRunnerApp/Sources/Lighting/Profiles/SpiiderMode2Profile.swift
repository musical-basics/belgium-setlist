import Foundation

/// Robe Robin Spiider — PROVISIONAL "Mode 2 / Basic" profile (~27 channels).
///
/// CONFIRMED present at the venue: the CC De Factorij rider lists "12 × Robe Spiider". We patch 2.
/// The DMX MODE, however, is set on the fixture per-show and is still CONFIRM — the operator/venue
/// tech chooses it on the day, so this map stays provisional until then.
///
/// The channel offsets below are taken from the OFFICIAL Robe Spiider DMX chart v2.3, Mode 2
/// "Basic" column (27 channels) — extracted directly from the PDF. They are NO LONGER guesses.
///
/// `isProvisional` STAYS `true` for one reason only: whether the physical fixture is actually
/// patched in Mode 2 is the operator's choice on the day. If it is set to Mode 1/3/4 instead, this
/// table is void and must be re-pulled from that mode's column. So the rig keeps the Spiiders dark
/// until the operator confirms Mode 2 and taps ARM MOVERS — then this verified map drives them.
///
/// Mode-2 specifics that matter: Pan/Tilt are 16-bit (coarse+fine); there is NO zoom-fine and NO
/// dimmer-fine (both 8-bit); colour channels are global "all pixels" (RGBW vs CMY depends on the
/// unit's mixing-mode menu); the shutter channel is 0–31 CLOSED / 32–63 open / 64–95 strobe.
public final class SpiiderMode2Profile: FixtureProfile {
    public let id = "spiider_mode2"
    public let label = "Robe Spiider (Mode 2 · PROVISIONAL)"
    /// CONFIRM: Mode 2 "Basic" is provisionally 27 channels.
    public let channelCount = 27
    /// Provisional until verified against the official chart for the confirmed mode.
    public let isProvisional = true

    /// 0-based channel offsets — PLACEHOLDER VALUES, replace from the official chart.
    /// Set an offset to `nil` for any parameter the confirmed mode does not expose.
    /// Verified Mode-2 (Basic) channel offsets, 0-based within the 27-ch footprint.
    /// Set an offset to `nil` for any parameter this mode does not expose.
    private enum Ch {
        static let pan: Int? = 0
        static let panFine: Int? = 1
        static let tilt: Int? = 2
        static let tiltFine: Int? = 3
        // offset 4 = Pan/Tilt speed, offset 5 = Power/Special functions — DELIBERATELY UNMAPPED.
        // Writing into offset 5 triggers fixture reset / DMX-mode / parking macros; leaving it at
        // 0 (zero-fill) is "Reserved/default" = safe.
        static let red: Int? = 7          // global "all pixels" colour, 8-bit
        static let green: Int? = 8
        static let blue: Int? = 9
        static let white: Int? = 10
        static let zoom: Int? = 24        // 8-bit (no zoom-fine in Mode 2)
        static let strobe: Int? = 25      // main shutter/strobe
        static let dimmer: Int? = 26      // main dimmer, 8-bit (no dimmer-fine in Mode 2)
    }

    public init() {}

    public func render(_ s: FixtureState, into u: DMXUniverse, startAddress addr: Int) {
        guard channelCount > 0 else { return }
        var bytes = [UInt8](repeating: 0, count: channelCount)

        put16(&bytes, Ch.pan, Ch.panFine, s.pan)
        put16(&bytes, Ch.tilt, Ch.tiltFine, s.tilt)

        // Shutter: "no strobe" MUST write 32 (open) — writing 0 leaves the shutter CLOSED (dark).
        put8(&bytes, Ch.strobe, shutterByte(s.strobe))

        put8(&bytes, Ch.red, DMX.byte(s.red))
        put8(&bytes, Ch.green, DMX.byte(s.green))
        put8(&bytes, Ch.blue, DMX.byte(s.blue))
        put8(&bytes, Ch.white, DMX.byte(s.white))
        put8(&bytes, Ch.zoom, DMX.byte(s.zoom))
        put8(&bytes, Ch.dimmer, DMX.byte(s.intensity))

        u.write(startAddress: addr, bytes: bytes)
    }

    /// Map 0…1 strobe onto the Mode-2 shutter: 32 = open (no strobe), 64…95 = strobe slow→fast.
    private func shutterByte(_ strobe: Double) -> UInt8 {
        guard strobe > 0.001 else { return 32 }   // open, no strobe (NOT 0 = closed)
        return UInt8((64 + 31 * min(1, max(0, strobe))).rounded())
    }

    @inline(__always)
    private func put8(_ bytes: inout [UInt8], _ offset: Int?, _ value: UInt8) {
        guard let o = offset, o >= 0, o < bytes.count else { return }
        bytes[o] = value
    }

    @inline(__always)
    private func put16(_ bytes: inout [UInt8], _ coarse: Int?, _ fine: Int?, _ v: Double) {
        let (c, f) = DMX.word(v)
        put8(&bytes, coarse, c)
        put8(&bytes, fine, f)
    }
}
