import Foundation

/// Robe T1 Profile — Mode 3 "Five colours" (53 channels), per the FINAL venue lighting plot
/// (`Lighting_Plot/Lions patchv01.pdf`): 2 × "Robe T1 Mode 3 - 53 ch" on universe 2 at 321 / 381,
/// hung upstage-centre — they read as back-key specials over the piano.
///
/// Channel map from the OFFICIAL Robe chart "Robin T1 Profile DMX charts" v2.1
/// (robe.cz/res/downloads/dmx_charts/Robin_T1_Profile_DMX_charts.pdf), Mode 3 column. Mode 3
/// exposes the five raw LED emitters directly — Red, Green, Blue, Amber, Lime — each 16-bit
/// (no CMY in this mode). Open white per the chart = all five emitters at full.
///
/// Park-value channels that are NOT 0 (the chart's own defaults — getting these wrong makes the
/// beam tinted, unfocused, or dark):
/// - ch 7/8 LED frequency 10/128 (600 Hz, no fine offset)
/// - ch 22 CTO = 110 → neutral 5600 K (0 would push 8000 K blue!)
/// - ch 23 green correction = 128 (uncorrected)
/// - ch 28/31/34 effect-wheel/gobo/prism rotation = 128 (no rotation)
/// - ch 40 focus = 128, ch 42 framing-module rotation = 128, blade swivels 44/46/48/50 = 128
/// - ch 51 shutter = 32 open (0 = CLOSED); strobe = 64–95
/// Zoom (ch 38) is INVERTED like the Spiider: DMX 0 = widest beam.
///
/// FixtureState mapping: red/green/blue drive their emitters; `white` lifts ALL five emitters
/// (max with the colour) so white=1 → chart-default open white. Amber/Lime aren't separately
/// addressable from timelines — a one-file edit here if an amber look is ever wanted.
///
/// `isProvisional` stays `true`: the plot says Mode 3, but the patched mode is physical state at
/// the venue — verify on the day, then ARM MOVERS.
public final class T1Mode3Profile: FixtureProfile {
    public let id = "t1_mode3"
    public let label = "Robe T1 Profile (Mode 3 · 53ch · plot-final, verify on day)"
    public let channelCount = 53
    public let isProvisional = true

    /// 0-based offsets within the 53-ch footprint (official chart v2.1, Mode 3 column).
    private enum Ch {
        static let pan = 0, panFine = 1
        static let tilt = 2, tiltFine = 3
        static let ptSpeed = 4            // 0 = standard
        static let power = 5              // DELIBERATELY 0 — special functions/resets
        static let ledFreq = 6            // 10 = 600 Hz default
        static let ledFreqFine = 7        // 128 = no offset
        static let colourFunctions = 8    // 0 = none
        static let cri = 9                // 0 = CRI standard
        static let virtualWheel = 10      // 0 = open / emitters in control
        static let red = 11, redFine = 12
        static let green = 13, greenFine = 14
        static let blue = 15, blueFine = 16
        static let amber = 17, amberFine = 18
        static let lime = 19, limeFine = 20
        static let cto = 21               // 110 = neutral 5600 K
        static let greenCorr = 22         // 128 = uncorrected
        static let colorMix = 23          // 0 = default priority
        static let goboSelSpeed = 24
        static let fxTime = 25
        static let effectWheelPos = 26
        static let effectWheelRot = 27    // 128 = no rotation
        static let effectAnim = 28
        static let rotGobo = 29           // 0 = open
        static let goboIndex = 30         // 128 = default index
        static let goboIndexFine = 31
        static let prism = 32             // 0 = out
        static let prismRot = 33          // 128 = no rotation
        static let frost = 34             // 0 = open
        static let iris = 35, irisFine = 36   // 0 = open
        static let zoom = 37, zoomFine = 38   // INVERTED: DMX 0 = widest
        static let focus = 39, focusFine = 40 // 128 = default
        static let framingRot = 41        // 128 = centred
        static let blade1 = 42, blade1Swivel = 43
        static let blade2 = 44, blade2Swivel = 45
        static let blade3 = 46, blade3Swivel = 47
        static let blade4 = 48, blade4Swivel = 49
        static let shutter = 50           // 32 = open, 64–95 = strobe
        static let dimmer = 51, dimmerFine = 52
    }

    public init() {}

    public func render(_ s: FixtureState, into u: DMXUniverse, startAddress addr: Int) {
        var bytes = [UInt8](repeating: 0, count: channelCount)

        put16(&bytes, Ch.pan, Ch.panFine, s.pan)
        // Tilt straight through. The whole mover rig hangs inverted vs the authored tilt
        // convention, but that flip is handled ONCE for every mover by the `invertTilt` stage
        // anchor in Rig.applyStageAnchor — do NOT flip again here or the two cancel and the
        // T1 back-key beam lands on the cyc/screen instead of the piano.
        put16(&bytes, Ch.tilt, Ch.tiltFine, s.tilt)

        // `white` lifts all five emitters (open white = all at full per the chart defaults).
        put16(&bytes, Ch.red, Ch.redFine, max(s.red, s.white))
        put16(&bytes, Ch.green, Ch.greenFine, max(s.green, s.white))
        put16(&bytes, Ch.blue, Ch.blueFine, max(s.blue, s.white))
        put16(&bytes, Ch.amber, Ch.amberFine, s.white)
        put16(&bytes, Ch.lime, Ch.limeFine, s.white)

        put16(&bytes, Ch.zoom, Ch.zoomFine, 1.0 - s.zoom)   // chart: 0 = widest
        put16(&bytes, Ch.dimmer, Ch.dimmerFine, s.intensity)

        // Park values per the official chart (see header) — everything else stays 0.
        bytes[Ch.ledFreq] = 10
        bytes[Ch.ledFreqFine] = 128
        bytes[Ch.cto] = 110
        bytes[Ch.greenCorr] = 128
        bytes[Ch.effectWheelRot] = 128
        bytes[Ch.goboIndex] = 128
        bytes[Ch.prismRot] = 128
        bytes[Ch.focus] = 128
        bytes[Ch.framingRot] = 128
        bytes[Ch.blade1Swivel] = 128
        bytes[Ch.blade2Swivel] = 128
        bytes[Ch.blade3Swivel] = 128
        bytes[Ch.blade4Swivel] = 128
        bytes[Ch.shutter] = DMXShutter.robeByte(s.strobe)

        u.write(startAddress: addr, bytes: bytes)
    }

    @inline(__always)
    private func put16(_ bytes: inout [UInt8], _ coarse: Int, _ fine: Int, _ v: Double) {
        let (c, f) = DMX.word(v)
        bytes[coarse] = c
        bytes[fine] = f
    }
}
