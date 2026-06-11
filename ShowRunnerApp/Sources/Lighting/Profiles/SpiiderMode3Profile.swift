import Foundation

/// Robe Robin Spiider — Mode 3 "Advanced" (33 channels), per the FINAL venue lighting plot
/// (`Lighting_Plot/Lions patchv01.pdf`): 8 × "Robe Spiider Mode 3 - 33ch" on universe 2 at
/// addresses 1 / 41 / 81 / 121 / 161 / 201 / 241 / 281.
///
/// Channel offsets are from the OFFICIAL Robe chart "Robin SPIIDER - DMX protocol" v2.3
/// (robe.cz/res/downloads/dmx_charts/Robin_SPIIDER_DMX_charts.pdf), Mode 3 column — extracted
/// directly from the PDF, not guessed. Mode 3 exposes GLOBAL (all-pixels) RGBW at 16-bit; the
/// per-pixel channels exist only in other modes.
///
/// Mode-3 specifics that matter:
/// - 16-bit pairs: pan 1+2, tilt 3+4, R 8+9, G 10+11, B 12+13, W 14+15, zoom 29+30, dimmer 32+33.
/// - Zoom direction is INVERTED vs our semantic: DMX 0 = WIDEST beam, 255 = narrowest, so this
///   profile writes `1 − zoom`.
/// - Main shutter (ch 31): 0–31 CLOSED, 32–63 open (32 = default), 64–95 strobe slow→fast.
///   "No strobe" MUST write 32 — writing 0 leaves the shutter closed (dark).
/// - Ch 6 (Power/Special) stays 0: values ≥10 held 3 s can latch resets / mode changes.
/// - Ch 7 (virtual colour wheel) stays 0 so the RGBW channels are in control.
/// - Ch 17 (colour-mix control) 0–9 = "Global priority" — our global RGBW rules the pixels.
/// - Flower effect (ch 21) stays 0 = OFF; its sub-channels (22–28) are parked at chart defaults.
///
/// `isProvisional` stays `true` for one reason only: paper vs reality. The plot SAYS Mode 3, but
/// the fixture's patched mode is physical state at the venue — verify on the day, then ARM MOVERS.
public final class SpiiderMode3Profile: FixtureProfile {
    public let id = "spiider_mode3"
    public let label = "Robe Spiider (Mode 3 · 33ch · plot-final, verify on day)"
    public let channelCount = 33
    public let isProvisional = true

    /// 0-based offsets within the 33-ch footprint (official chart v2.3, Mode 3 column).
    private enum Ch {
        static let pan = 0, panFine = 1
        static let tilt = 2, tiltFine = 3
        static let ptSpeed = 4          // 0 = standard
        static let power = 5            // DELIBERATELY 0 — special functions/resets live here
        static let virtualWheel = 6     // 0 = open / RGBW in control
        static let red = 7, redFine = 8
        static let green = 9, greenFine = 10
        static let blue = 11, blueFine = 12
        static let white = 13, whiteFine = 14
        static let ctc = 15             // 0 = no colour-temperature correction
        static let colorMix = 16        // 0–9 = global priority
        static let pixelFx = 17, pixelFxSpeed = 18, pixelFxFade = 19   // 0 = off
        static let flower = 20          // 0 = flower effect OFF
        static let flowerR = 21, flowerG = 22, flowerB = 23, flowerW = 24
        static let flowerMacro = 25
        static let flowerShutter = 26   // parked at 32 (its open default)
        static let flowerDimmer = 27    // 0
        static let zoom = 28, zoomFine = 29   // INVERTED: DMX 0 = widest
        static let shutter = 30         // 32 = open, 64–95 = strobe
        static let dimmer = 31, dimmerFine = 32
    }

    public init() {}

    public func render(_ s: FixtureState, into u: DMXUniverse, startAddress addr: Int) {
        var bytes = [UInt8](repeating: 0, count: channelCount)

        put16(&bytes, Ch.pan, Ch.panFine, s.pan)
        put16(&bytes, Ch.tilt, Ch.tiltFine, s.tilt)
        put16(&bytes, Ch.red, Ch.redFine, s.red)
        put16(&bytes, Ch.green, Ch.greenFine, s.green)
        put16(&bytes, Ch.blue, Ch.blueFine, s.blue)
        put16(&bytes, Ch.white, Ch.whiteFine, s.white)
        put16(&bytes, Ch.zoom, Ch.zoomFine, 1.0 - s.zoom)   // chart: 0 = widest
        put16(&bytes, Ch.dimmer, Ch.dimmerFine, s.intensity)

        bytes[Ch.shutter] = DMXShutter.robeByte(s.strobe)
        bytes[Ch.flowerShutter] = 32   // chart default (inert while flower = 0)
        // Everything else (ptSpeed, power, virtualWheel, ctc, colorMix, pixel fx, flower) stays 0.

        u.write(startAddress: addr, bytes: bytes)
    }

    @inline(__always)
    private func put16(_ bytes: inout [UInt8], _ coarse: Int, _ fine: Int, _ v: Double) {
        let (c, f) = DMX.word(v)
        bytes[coarse] = c
        bytes[fine] = f
    }
}

/// Robe's shutter scheme, shared by the Spiider (Mode 3 ch 31) and T1 Profile (Mode 3 ch 51):
/// 0–31 closed · 32–63 open (32 = default) · 64–95 strobe slow→fast.
enum DMXShutter {
    static func robeByte(_ strobe: Double) -> UInt8 {
        guard strobe > 0.001 else { return 32 }   // open, no strobe (NOT 0 = closed!)
        return UInt8((64 + 31 * min(1, max(0, strobe))).rounded())
    }
}
