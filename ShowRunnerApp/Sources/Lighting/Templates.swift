import Foundation

/// The 12 pieces collapse into three lighting "languages". These builders turn a small set of
/// per-piece parameters (a cyc colour, an intensity) into reusable looks, so the quiet pieces
/// are not over-lit and stay consistent. SOLO/TRIO produce a cue list (manual advance); EDM
/// produces a data timeline (timecode-driven), normally loaded from a JSON file but also
/// synthesizable here for cloning the reference piece to the other EDM tracks.

public enum SoloTemplate {
    /// SOLO: mostly static, piano lit clean, one cyc colour with slow drift, movers parked.
    /// 2–3 state changes. `cyc` is the cyclorama colour [r,g,b] 0…1.
    public static func build(piece: String, cyc: [Double], intensity: Double) -> CueList {
        let c = rgb(cyc)
        // Front wash: a clean, slightly warm key on the piano (Fargos), restrained.
        var key = FixtureState()
        key.red = 1.0; key.green = 0.78; key.blue = 0.55; key.white = 0.85
        key.intensity = intensity
        key.zoom = 0.35

        // Cyc colour at a low, calm level (the named colour).
        let cycLow = FixtureState.rgb(c.r, c.g, c.b, intensity: 0.45)
        let cycDrift = FixtureState.rgb(c.r * 0.7 + 0.1, c.g * 0.7, c.b * 0.8 + 0.15, intensity: 0.55)

        // Movers parked: dark and centred (no movement on the quiet pieces).
        var parked = FixtureState(); parked.intensity = 0; parked.pan = 0.5; parked.tilt = 0.55

        return CueList(piece: piece, cues: [
            Cue(label: "Settle", fadeSeconds: 3.0, states: ["Fargos": key, "Dalis": cycLow, "Spiiders": parked]),
            Cue(label: "Drift",  fadeSeconds: 25.0, states: ["Dalis": cycDrift]),               // slow colour drift
            Cue(label: "Out",    fadeSeconds: 4.0, states: ["All": FixtureState.blackout()]),
        ])
    }
}

public enum TrioTemplate {
    /// TRIO: a wider, warm wash so all three players read evenly; slightly richer cyc; restrained.
    public static func build(piece: String, cyc: [Double], intensity: Double) -> CueList {
        let c = rgb(cyc)
        var wash = FixtureState()
        wash.red = 1.0; wash.green = 0.82; wash.blue = 0.60; wash.white = 1.0
        wash.intensity = intensity
        wash.zoom = 0.7   // wider so three players are covered evenly

        let cycRich = FixtureState.rgb(c.r, c.g, c.b, intensity: 0.7)
        var parked = FixtureState(); parked.intensity = 0; parked.pan = 0.5; parked.tilt = 0.55

        return CueList(piece: piece, cues: [
            Cue(label: "Trio up", fadeSeconds: 3.0, states: ["Fargos": wash, "Dalis": cycRich, "Spiiders": parked]),
            Cue(label: "Lift",    fadeSeconds: 8.0, states: ["Fargos": brighten(wash, by: 0.1)]),
            Cue(label: "Out",     fadeSeconds: 4.0, states: ["All": FixtureState.blackout()]),
        ])
    }
}

/// A musical section, used to synthesize an EDM timeline. Times are SECONDS into the track —
/// these come from analyzing the audio (intro/build/drop/breakdown/outro) and must be set per
/// piece. The builder maps each section kind to the lighting behaviour the brief specifies.
public struct EDMSection {
    public enum Kind: String { case intro, build, drop, breakdown, outro }
    public var kind: Kind
    public var start: Double
    public init(_ kind: Kind, _ start: Double) { self.kind = kind; self.start = start }
}

public enum EDMTemplate {
    /// Synthesize a timecoded timeline from section markers + a palette. The two Spiiders move
    /// symmetrically (mirrored pan) so the movement reads as intentional. Drops get the biggest
    /// moves + full colour hits + strobe accents + zoom punches; builds ramp; breakdowns pull
    /// back to the cyc; intro/outro stay minimal. Use this to clone the reference EDM piece.
    ///
    /// `palette` is an ordered list of [r,g,b] the piece moves through (no rainbow-cycling).
    public static func build(piece: String, sections: [EDMSection], palette: [[Double]], totalSeconds: Double) -> Timeline {
        let pal = palette.isEmpty ? [[0.1, 0.2, 0.9], [0.9, 0.1, 0.3]] : palette
        var fargo: [Keyframe] = []
        var spiiderA: [Keyframe] = []
        var spiiderB: [Keyframe] = []
        var dalis: [Keyframe] = []

        for (i, sec) in sections.enumerated() {
            let color = rgb(pal[i % pal.count])
            let t = sec.start
            switch sec.kind {
            case .intro:
                fargo.append(Keyframe(t: t, ease: .smooth, state: FixtureState.rgb(color.r, color.g, color.b, intensity: 0.25)))
                dalis.append(Keyframe(t: t, ease: .smooth, state: FixtureState.rgb(color.r, color.g, color.b, intensity: 0.3)))
                spiiderA.append(parked(t))
                spiiderB.append(parked(t))
            case .build:
                fargo.append(Keyframe(t: t, ease: .linear, state: beam(color, intensity: 0.6, zoom: 0.4)))
                spiiderA.append(sweep(t, pan: 0.35, tilt: 0.45, color: color, intensity: 0.6))
                spiiderB.append(sweep(t, pan: 0.65, tilt: 0.45, color: color, intensity: 0.6)) // mirrored pan
            case .drop:
                var hit = beam(color, intensity: 1.0, zoom: 0.9)
                hit.strobe = 0.0
                fargo.append(Keyframe(t: t, ease: .hold, state: hit)) // instant full-intensity colour hit
                fargo.append(Keyframe(t: t + 0.12, ease: .hold, state: punchZoom(hit))) // zoom punch
                spiiderA.append(bigMove(t, pan: 0.1, tilt: 0.2, color: color))
                spiiderB.append(bigMove(t, pan: 0.9, tilt: 0.2, color: color)) // mirrored
                dalis.append(Keyframe(t: t, ease: .hold, state: FixtureState.rgb(color.r, color.g, color.b, intensity: 0.9)))
            case .breakdown:
                fargo.append(Keyframe(t: t, ease: .smooth, state: FixtureState.rgb(color.r, color.g, color.b, intensity: 0.3)))
                dalis.append(Keyframe(t: t, ease: .smooth, state: FixtureState.rgb(color.r, color.g, color.b, intensity: 0.5)))
                spiiderA.append(sweep(t, pan: 0.45, tilt: 0.5, color: color, intensity: 0.3))
                spiiderB.append(sweep(t, pan: 0.55, tilt: 0.5, color: color, intensity: 0.3))
            case .outro:
                fargo.append(Keyframe(t: t, ease: .smooth, state: FixtureState.rgb(color.r, color.g, color.b, intensity: 0.15)))
                dalis.append(Keyframe(t: t, ease: .smooth, state: FixtureState.rgb(color.r, color.g, color.b, intensity: 0.2)))
                spiiderA.append(parked(t)); spiiderB.append(parked(t))
            }
        }
        // Tidy blackout at the very end.
        fargo.append(Keyframe(t: totalSeconds, ease: .smooth, state: .blackout()))
        dalis.append(Keyframe(t: totalSeconds, ease: .smooth, state: .blackout()))
        spiiderA.append(Keyframe(t: totalSeconds, ease: .smooth, state: parkedState()))
        spiiderB.append(Keyframe(t: totalSeconds, ease: .smooth, state: parkedState()))

        return Timeline(piece: piece, template: "edm", durationSeconds: totalSeconds, tracks: [
            FixtureTrack(fixture: "Fargos", keyframes: fargo),
            FixtureTrack(fixture: "Spiider1", keyframes: spiiderA),
            FixtureTrack(fixture: "Spiider2", keyframes: spiiderB),
            FixtureTrack(fixture: "Dalis", keyframes: dalis),
        ])
    }

    // helpers
    private static func beam(_ c: (r: Double, g: Double, b: Double), intensity: Double, zoom: Double) -> FixtureState {
        var s = FixtureState.rgb(c.r, c.g, c.b, intensity: intensity); s.zoom = zoom; return s
    }
    private static func punchZoom(_ s: FixtureState) -> FixtureState { var x = s; x.zoom = 0.1; return x }
    private static func sweep(_ t: Double, pan: Double, tilt: Double, color c: (r: Double, g: Double, b: Double), intensity: Double) -> Keyframe {
        var s = FixtureState.rgb(c.r, c.g, c.b, intensity: intensity)
        s.pan = pan; s.tilt = tilt; s.zoom = 0.5
        return Keyframe(t: t, ease: .smooth, state: s)
    }
    private static func bigMove(_ t: Double, pan: Double, tilt: Double, color c: (r: Double, g: Double, b: Double)) -> Keyframe {
        var s = FixtureState.rgb(c.r, c.g, c.b, intensity: 1.0)
        s.pan = pan; s.tilt = tilt; s.zoom = 0.85
        return Keyframe(t: t, ease: .smooth, state: s)
    }
    private static func parked(_ t: Double) -> Keyframe { Keyframe(t: t, ease: .smooth, state: parkedState()) }
    private static func parkedState() -> FixtureState { var s = FixtureState(); s.intensity = 0; s.pan = 0.5; s.tilt = 0.55; return s }
}

// MARK: - shared helpers

private func rgb(_ a: [Double]) -> (r: Double, g: Double, b: Double) {
    let r = a.count > 0 ? a[0] : 0
    let g = a.count > 1 ? a[1] : 0
    let b = a.count > 2 ? a[2] : 0
    return (r, g, b)
}
private func brighten(_ s: FixtureState, by d: Double) -> FixtureState {
    var x = s; x.intensity = min(1, s.intensity + d); return x
}
