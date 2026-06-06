import Foundation

/// Robert Juliat 860 Dalis — implemented as Mode 3 "Full 1 group mode 8b" (13 channels).
///
/// CONFIRMED model (CC De Factorij rider): "14 × Robert Juliat 860 Dalis MKII" — a ROBERT JULIAT
/// LED cyclorama/wash with 8 emitters (Red, Green, Blue, Royal Blue, Cyan, Amber, Cool White, Warm
/// White), NOT a Robe product. We patch 2 of them as cyc colour.
///
/// The channel map below is from the OFFICIAL Robert Juliat Dalis 860 manual (DN41077600-B,
/// V2.XX), Mode 3 — the smallest single-cell mode that exposes the emitters directly. It is
/// therefore a real, verified map, NOT a stub.
///
/// `isProvisional` STAYS `true` because (a) this is the V2.XX manual and the venue unit is a
/// "MKII" — RJ keeps mode NAMES but channel counts can shift between revisions, and (b) the
/// operator still has to patch the fixture in Mode 3 (SETUP ▸ DMX ▸ PERSONALITY). So the rig keeps
/// the Dalis dark until the operator confirms Mode 3 and taps ARM MOVERS — then this map drives it.
/// (The class/id name keeps "stub" only so lighting.json doesn't need re-patching.)
public final class DalisStubProfile: FixtureProfile {
    public let id = "dalis_stub"
    public let label = "Robert Juliat 860 Dalis MKII (Mode 3 · provisional)"
    /// Mode 3 "Full 1 group mode 8b". CONFIRM the MKII unit reports 13 channels in this mode.
    public let channelCount = 13
    public let isProvisional = true

    /// Verified Mode-3 offsets (0-based). Emitters with no matching FixtureState field are left
    /// at 0 (dark) — fine for an RGBW-style cyc wash.
    private enum Ch {
        static let dimmer = 0          // master intensity
        static let red = 1
        static let green = 2
        static let blue = 3
        static let royalBlue = 4       // no FixtureState field → 0
        static let cyan = 5            // no FixtureState field → 0
        static let amber = 6           // no FixtureState field → 0
        static let coolWhite = 7       // FixtureState.white maps here
        static let warmWhite = 8       // no FixtureState field → 0
        static let strobeDuration = 9  // 0 = off; 1…255 = flash length
        static let strobeSpeed = 10    // frequency 5.8…11.5 Hz
        static let responseTime = 11   // 0–250 = 0.1…4s smoothing; 251–255 = OFF
        static let controlMode = 12    // 0 = RDM enabled
    }

    public init() {}

    public func render(_ s: FixtureState, into u: DMXUniverse, startAddress addr: Int) {
        guard channelCount > 0 else { return }
        var bytes = [UInt8](repeating: 0, count: channelCount)

        bytes[Ch.dimmer] = DMX.byte(s.intensity)
        bytes[Ch.red]    = DMX.byte(s.red)
        bytes[Ch.green]  = DMX.byte(s.green)
        bytes[Ch.blue]   = DMX.byte(s.blue)
        bytes[Ch.coolWhite] = DMX.byte(s.white)   // single white field → Cool White

        if s.strobe > 0.001 {
            bytes[Ch.strobeDuration] = DMX.byte(s.strobe)   // 1…255 flash length
            bytes[Ch.strobeSpeed] = 128                     // mid frequency
        }
        // Disable fixture-side smoothing so the app's own fades aren't double-smoothed (251 = OFF).
        bytes[Ch.responseTime] = 255

        u.write(startAddress: addr, bytes: bytes)
    }
}
