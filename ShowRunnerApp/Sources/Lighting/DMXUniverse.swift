import Foundation

/// One DMX512 universe: a fixed 512-slot frame of 8-bit levels.
///
/// Slots are addressed by the DMX standard's 1-based address (1…512); internally they live
/// in a 0-based `[UInt8]` of length 512. The sACN layer prepends the 0x00 start code when it
/// builds a packet — this buffer holds ONLY the 512 channel levels, never the start code.
public final class DMXUniverse {
    /// The sACN universe number this frame is transmitted on (a CONFIRM value, from config).
    public let number: Int
    /// 512 channel levels, index 0 == DMX address 1.
    public private(set) var slots: [UInt8]

    public init(number: Int) {
        self.number = number
        self.slots = [UInt8](repeating: 0, count: 512)
    }

    /// Zero every slot (used for blackout and at the start of each render frame).
    public func clear() {
        for i in 0..<slots.count { slots[i] = 0 }
    }

    /// Set a single 1-based DMX address. Out-of-range addresses are ignored (never crashes).
    @inline(__always)
    public func set(address: Int, value: UInt8) {
        let i = address - 1
        guard i >= 0, i < slots.count else { return }
        slots[i] = value
    }

    /// Write a run of bytes starting at a 1-based DMX address. Anything past slot 512 is
    /// silently dropped, so a mis-patched fixture can never overflow the frame.
    public func write(startAddress: Int, bytes: [UInt8]) {
        var addr = startAddress
        for b in bytes {
            set(address: addr, value: b)
            addr += 1
        }
    }

    /// Snapshot of the 512 levels (for the sACN sender / tests).
    public func snapshot() -> [UInt8] { slots }
}

/// Helpers for turning normalized 0…1 parameters into DMX bytes, including 16-bit splits.
public enum DMX {
    /// 0…1 → a single 0…255 byte (rounded, clamped).
    @inline(__always)
    public static func byte(_ v: Double) -> UInt8 {
        let clamped = min(1.0, max(0.0, v))
        return UInt8((clamped * 255.0).rounded())
    }

    /// 0…1 → a 16-bit (coarse, fine) pair, e.g. for 16-bit dimmer / pan / tilt.
    @inline(__always)
    public static func word(_ v: Double) -> (coarse: UInt8, fine: UInt8) {
        let clamped = min(1.0, max(0.0, v))
        let value = UInt16((clamped * 65535.0).rounded())
        return (UInt8(value >> 8), UInt8(value & 0xFF))
    }
}
