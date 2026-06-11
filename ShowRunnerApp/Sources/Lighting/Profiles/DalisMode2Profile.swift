import Foundation

/// Robert Juliat Dalis 860 MKII — Mode 2 "Full 1 group mode 16b" (22 channels), per the FINAL
/// venue lighting plot (`Lighting_Plot/Lions patchv01.pdf`): 7 × "Robert Juliat Dalis 860 MKII
/// Mode 2 22ch" on universe 3 at 67 / 89 / 111 / 133 / 155 / 177 / 199 (plot labels Dalis 4–10),
/// hung as one cyclorama row upstage.
///
/// Channel map from the OFFICIAL Robert Juliat Dalis 860 manual DN41077600-B (V2.XX), §5.2.4:
/// Mode 2 is verbatim "Full 1 group mode 16b", exactly 22 channels — dimmer + all 8 emitters at
/// 16-bit, then strobe duration/speed, response time, control mode. The manual's emitter order is
/// Red, Green, Blue, Royal blue, Cyan, Amber, Cool white (6500 K), Warm white (2200 K).
///
/// `isProvisional` is FALSE: the plot's "Mode 2 22ch" matches the official manual's Mode 2 channel
/// count exactly, the fixture has no movement/shutter to misbehave, and the show needs a working
/// cyc (and a PROOF OF LIFE target) without arming. Worst case of a paper/reality mismatch is a
/// wrong colour, not a hazard — still sanity-check colours at soundcheck.
///
/// Emitters with no FixtureState field (Royal blue, Cyan, Amber, Warm white) stay at 0; the wash
/// is RGB + Cool white, which is what the timelines author. Tune on the rig if a deeper blue
/// (Royal blue) or warmer white is wanted — one-file edit here.
public final class DalisMode2Profile: FixtureProfile {
    public let id = "dalis_mode2"
    public let label = "Robert Juliat Dalis 860 MKII (Mode 2 · 22ch · live)"
    public let channelCount = 22
    public let isProvisional = false

    /// 0-based offsets (official manual, Mode 2). All colour/dimmer channels are 16-bit pairs.
    private enum Ch {
        static let dimmer = 0, dimmerFine = 1
        static let red = 2, redFine = 3
        static let green = 4, greenFine = 5
        static let blue = 6, blueFine = 7
        static let royalBlue = 8, royalBlueFine = 9     // unused → 0
        static let cyan = 10, cyanFine = 11             // unused → 0
        static let amber = 12, amberFine = 13           // unused → 0
        static let coolWhite = 14, coolWhiteFine = 15   // FixtureState.white maps here
        static let warmWhite = 16, warmWhiteFine = 17   // unused → 0
        static let strobeDuration = 18  // 0 = strobe OFF (open); 1–255 = flash 1…85 ms
        static let strobeSpeed = 19     // 5.8…11.5 Hz (only acts while duration ≥ 1)
        static let responseTime = 20    // 0–250 = 0.1…4 s smoothing; 251–255 = OFF
        static let controlMode = 21     // 0 = default (RDM active)
    }

    public init() {}

    public func render(_ s: FixtureState, into u: DMXUniverse, startAddress addr: Int) {
        var bytes = [UInt8](repeating: 0, count: channelCount)

        put16(&bytes, Ch.dimmer, Ch.dimmerFine, s.intensity)
        put16(&bytes, Ch.red, Ch.redFine, s.red)
        put16(&bytes, Ch.green, Ch.greenFine, s.green)
        put16(&bytes, Ch.blue, Ch.blueFine, s.blue)
        put16(&bytes, Ch.coolWhite, Ch.coolWhiteFine, s.white)

        if s.strobe > 0.001 {
            bytes[Ch.strobeDuration] = max(1, DMX.byte(s.strobe))
            bytes[Ch.strobeSpeed] = 128   // mid frequency (~8.6 Hz)
        }
        // Disable fixture-side smoothing so the app's own fades aren't double-smoothed.
        bytes[Ch.responseTime] = 255

        u.write(startAddress: addr, bytes: bytes)
    }

    @inline(__always)
    private func put16(_ bytes: inout [UInt8], _ coarse: Int, _ fine: Int, _ v: Double) {
        let (c, f) = DMX.word(v)
        bytes[coarse] = c
        bytes[fine] = f
    }
}
