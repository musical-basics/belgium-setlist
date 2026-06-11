import Foundation

/// How a keyframe is reached from the previous one.
public enum Ease: String, Codable {
    case hold      // step: hold the previous value until this keyframe's time, then jump
    case linear    // straight ramp
    case smooth    // eased ramp (smoothstep) — used for musical, non-mechanical moves
}

/// One point on a fixture's timeline: the target state at time `t`, reached with `ease`.
public struct Keyframe: Codable {
    public var t: Double
    public var ease: Ease
    public var state: FixtureState

    public init(t: Double, ease: Ease = .smooth, state: FixtureState) {
        self.t = t; self.ease = ease; self.state = state
    }

    private enum CodingKeys: String, CodingKey { case t, ease, state }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        t = try c.decodeIfPresent(Double.self, forKey: .t) ?? 0
        ease = try c.decodeIfPresent(Ease.self, forKey: .ease) ?? .smooth
        state = try c.decodeIfPresent(FixtureState.self, forKey: .state) ?? FixtureState()
    }
}

/// A keyframe sequence for one logical fixture (or fixture group token, see Timeline below).
public struct FixtureTrack: Codable {
    public var fixture: String
    public var keyframes: [Keyframe]

    public init(fixture: String, keyframes: [Keyframe]) {
        self.fixture = fixture
        self.keyframes = keyframes.sorted { $0.t < $1.t }
    }

    /// Sample the interpolated state at time `t` (seconds). Clamps to the ends.
    public func sample(at t: Double) -> FixtureState {
        guard let first = keyframes.first else { return FixtureState() }
        if t <= first.t { return first.state }
        guard let last = keyframes.last, keyframes.count > 1 else { return first.state }
        if t >= last.t { return last.state }
        for i in 1..<keyframes.count {
            let a = keyframes[i - 1], b = keyframes[i]
            if t < b.t {
                let span = b.t - a.t
                let f = span > 0 ? (t - a.t) / span : 1
                switch b.ease {
                case .hold:   return a.state
                case .linear: return FixtureState.lerp(a.state, b.state, f)
                case .smooth: return FixtureState.lerp(a.state, b.state, Timeline.smoothstep(f))
                }
            }
        }
        return last.state
    }
}

/// A full piece's lighting, as data. `fixture` tokens in tracks are resolved by the renderer
/// against the rig; a track may name a single fixture ("Spiider1") or a group ("T1s",
/// "Spiiders", "All") so a chase can address many fixtures from one track.
public struct Timeline: Codable {
    public var piece: String          // piece order, informational
    public var template: String       // "edm" | "solo" | "trio" (informational)
    public var durationSeconds: Double?
    public var tracks: [FixtureTrack]

    public init(piece: String, template: String, durationSeconds: Double? = nil, tracks: [FixtureTrack]) {
        self.piece = piece; self.template = template
        self.durationSeconds = durationSeconds; self.tracks = tracks
    }

    @inline(__always)
    static func smoothstep(_ x: Double) -> Double {
        let t = min(1.0, max(0.0, x))
        return t * t * (3 - 2 * t)
    }

    /// Load a timeline from a JSON file. Returns nil (and reports) on any error — never throws.
    public static func load(from url: URL, onWarn: (String) -> Void = { _ in }) -> Timeline? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            onWarn("Timeline not found: \(url.lastPathComponent)")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Timeline.self, from: data)
        } catch {
            onWarn("Failed to parse timeline \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}

// MARK: - Sparse Codable for FixtureState (timeline JSON can specify only the fields it needs)

extension FixtureState: Codable {
    private enum CodingKeys: String, CodingKey {
        case intensity, red, green, blue, white, strobe, pan, tilt, zoom, colorMacro
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Clamp every decoded value to 0…1 so a hand-edited timeline typo (e.g. intensity: 10)
        // can't produce surprising output — values are normalized, profiles map them to DMX.
        func clamp(_ v: Double?) -> Double? { v.map { min(1.0, max(0.0, $0)) } }
        intensity  = clamp(try c.decodeIfPresent(Double.self, forKey: .intensity))  ?? intensity
        red        = clamp(try c.decodeIfPresent(Double.self, forKey: .red))        ?? red
        green      = clamp(try c.decodeIfPresent(Double.self, forKey: .green))      ?? green
        blue       = clamp(try c.decodeIfPresent(Double.self, forKey: .blue))       ?? blue
        white      = clamp(try c.decodeIfPresent(Double.self, forKey: .white))      ?? white
        strobe     = clamp(try c.decodeIfPresent(Double.self, forKey: .strobe))     ?? strobe
        pan        = clamp(try c.decodeIfPresent(Double.self, forKey: .pan))        ?? pan
        tilt       = clamp(try c.decodeIfPresent(Double.self, forKey: .tilt))       ?? tilt
        zoom       = clamp(try c.decodeIfPresent(Double.self, forKey: .zoom))       ?? zoom
        colorMacro = clamp(try c.decodeIfPresent(Double.self, forKey: .colorMacro)) ?? colorMacro
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intensity, forKey: .intensity)
        try c.encode(red, forKey: .red); try c.encode(green, forKey: .green)
        try c.encode(blue, forKey: .blue); try c.encode(white, forKey: .white)
        try c.encode(strobe, forKey: .strobe)
        try c.encode(pan, forKey: .pan); try c.encode(tilt, forKey: .tilt)
        try c.encode(zoom, forKey: .zoom); try c.encode(colorMacro, forKey: .colorMacro)
    }
}
