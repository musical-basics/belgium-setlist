import Foundation

/// The ONLY contract between the lighting module and the host app.
///
/// The host (ShowRunner) supplies an object conforming to this protocol; the lighting
/// renderer *reads* it every frame to learn the playback position of the current piece.
/// Lighting never imports the audio engine, never holds a reference to any host type
/// other than through this read-only protocol, and never writes anything back. That is
/// what guarantees the lighting code cannot affect the sound code.
///
/// All members are reads of values the audio engine already publishes for its own UI
/// (`elapsedSeconds`, `isPlaying`); reading them from the lighting thread is a benign,
/// lock-free read of a plain `Int`/`Bool`, exactly as the operator UI already does.
public protocol ShowClock: AnyObject {
    /// Playback position of the active audio piece, in seconds. 0 when nothing is playing.
    var positionSeconds: Double { get }

    /// True while audio is actively playing (an EDM piece is running).
    var isRunning: Bool { get }
}

/// A trivial clock used for headless tests / when no host clock is supplied.
/// Always reports "stopped at 0", so the renderer falls back to cue mode.
public final class NullShowClock: ShowClock {
    public init() {}
    public var positionSeconds: Double { 0 }
    public var isRunning: Bool { false }
}
