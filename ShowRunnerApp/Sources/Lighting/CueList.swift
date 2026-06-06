import Foundation

/// One lighting state change for a cue-advanced piece (SOLO / TRIO). A cue names a target
/// state per fixture (or per group token) and a fade time to reach it. The operator advances
/// through the cue list manually from the Lighting window — the safe, simple model the brief
/// calls for on the quiet pieces ("Cue-advance is fine here; timecode optional").
public struct Cue {
    public var label: String
    public var fadeSeconds: Double
    /// Target state keyed by fixture name or group token ("Fargos", "Spiiders", "Dalis", "All").
    public var states: [String: FixtureState]

    public init(label: String, fadeSeconds: Double, states: [String: FixtureState]) {
        self.label = label
        self.fadeSeconds = fadeSeconds
        self.states = states
    }
}

/// An ordered list of cues for one piece, advanced manually.
public struct CueList {
    public var piece: String
    public var cues: [Cue]
    public init(piece: String, cues: [Cue]) { self.piece = piece; self.cues = cues }
}
