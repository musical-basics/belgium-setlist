import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Native sACN (ANSI E1.31-2016) DATA-packet transmitter over UDP. No third-party dependencies.
///
/// Byte layout is built exactly to the verified spec: a full 512-slot Null-START data packet is
/// 638 bytes (UDP payload). Multi-byte fields are big-endian. The three PDU length fields and the
/// per-universe sequence counter are computed, never hardcoded, so partial frames stay valid too.
///
/// Output target is configurable (a CONFIRM value): multicast (239.255.<hi>.<lo> per universe) for
/// network-direct rigs, or unicast to a node's IP. On a Mac with more than one network interface,
/// set `interfaceIP` (or use unicast) so sACN doesn't leave via Wi-Fi instead of the lighting LAN.
public final class SACNSender {
    public enum Mode { case multicast, unicast }

    private let mode: Mode
    private let unicastHost: String
    private let interfaceIP: String?
    private let port: UInt16
    private let cid: [UInt8]            // 16 bytes
    private let sourceName64: [UInt8]   // exactly 64 bytes, UTF-8, null-padded
    private let onLog: (String) -> Void

    private var fd: Int32 = -1
    private var sequence: [Int: UInt8] = [:]   // independent per universe
    /// Guards `fd` and `sequence`. Sends come from the render queue, but `closeSocket()`/`isOpen`
    /// can be called from other threads at shutdown — the lock keeps those races safe.
    private let lock = NSLock()

    /// E1.31 full-frame packet constants (verified).
    private static let packetBytes = 638      // 126 header + 512 slots
    private static let slotCount = 512

    public init(mode: Mode,
                unicastHost: String,
                interfaceIP: String?,
                port: UInt16,
                cid: [UInt8],
                sourceName: String,
                onLog: @escaping (String) -> Void = { _ in }) {
        self.mode = mode
        self.unicastHost = unicastHost
        self.interfaceIP = (interfaceIP?.isEmpty == false) ? interfaceIP : nil
        self.port = port
        self.cid = cid.count == 16 ? cid : [UInt8](repeating: 0, count: 16)
        self.onLog = onLog

        // Source name: UTF-8, null-terminated, zero-padded to exactly 64 bytes.
        var name = Array(sourceName.utf8.prefix(63))
        name.append(contentsOf: [UInt8](repeating: 0, count: 64 - name.count))
        self.sourceName64 = name

        openSocket()
    }

    deinit { closeSocket() }

    public var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return fd >= 0 }

    // MARK: Socket

    private func openSocket() {
        let s = socket(AF_INET, SOCK_DGRAM, 0)
        guard s >= 0 else { onLog("sACN: socket() failed (errno \(errno))"); return }
        lock.lock(); fd = s; lock.unlock()

        // Multicast TTL = 1 (stay on the local segment unless the rig is routed).
        var ttl: UInt8 = 1
        _ = setsockopt(s, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        // Bound send timeout so a wedged/saturated lighting NIC can never park the render queue
        // (and with it the BLACKOUT/HOLD controls). A dropped sACN frame is harmless — the next
        // 40 fps frame is a full-state refresh that overwrites it.
        var tv = timeval(tv_sec: 0, tv_usec: 50_000)
        _ = setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Pin the outgoing interface for multicast if the operator named one. Without this, a
        // multi-NIC Mac sends sACN out its DEFAULT route (usually Wi-Fi / the house LAN) while the
        // rig listens on the lighting LAN — packets leave, nothing arrives. The spec may be an
        // interface name ("en14"), a subnet prefix ("192.168.202"), or a literal local IP.
        if mode == .multicast, let spec = interfaceIP {
            if let r = SACNSender.resolveInterface(spec) {
                var inaddr = r.addr
                let rc = setsockopt(s, IPPROTO_IP, IP_MULTICAST_IF, &inaddr, socklen_t(MemoryLayout<in_addr>.size))
                if rc != 0 { onLog("sACN: could not bind multicast interface \(r.label) (errno \(errno))") }
                else { onLog("sACN: multicast egress pinned to \(r.label)") }
            } else {
                onLog("sACN: interface '\(spec)' not found — multicast will use the DEFAULT route (may be the wrong NIC). Available IPv4: \(SACNSender.availableIPv4Interfaces())")
            }
        }
        onLog("sACN: socket open (\(mode == .multicast ? "multicast" : "unicast → \(unicastHost)"), port \(port))")
    }

    public func closeSocket() {
        lock.lock(); defer { lock.unlock() }
        if fd >= 0 { close(fd); fd = -1 }
    }

    // MARK: Send

    /// Send one universe's 512 levels. `slots` may be shorter (rest padded with 0).
    /// `terminated` sets the Stream_Terminated option bit (used by `sendTermination`).
    public func send(universe: Int, slots: [UInt8], terminated: Bool = false) {
        guard universe >= 1, universe <= 63999 else { onLog("sACN: universe \(universe) out of range 1…63999"); return }

        // Hold the lock across the fd read, sequence bump, and sendto so a concurrent closeSocket()
        // can't close the fd out from under the send. Sends are serialized on the render queue, so
        // there is no contention on the hot path; only shutdown ever contends.
        lock.lock(); defer { lock.unlock() }
        guard fd >= 0 else { return }

        let seq = sequence[universe] ?? 0
        sequence[universe] = seq &+ 1

        let packet = buildPacket(universe: universe, slots: slots, sequence: seq,
                                 options: terminated ? 0x40 : 0x00)
        guard var dest = destination(for: universe) else { return }

        let n = packet.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &dest) { ap -> Int in
                ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if n < 0 { onLog("sACN: sendto failed for universe \(universe) (errno \(errno))") }
    }

    /// Graceful shutdown for a universe: per E1.31, send 3 Stream_Terminated packets of zeros.
    public func sendTermination(universe: Int) {
        let zeros = [UInt8](repeating: 0, count: SACNSender.slotCount)
        for _ in 0..<3 { send(universe: universe, slots: zeros, terminated: true) }
    }

    // MARK: Packet construction (byte-exact to ANSI E1.31-2016)

    private func buildPacket(universe: Int, slots: [UInt8], sequence: UInt8, options: UInt8) -> [UInt8] {
        let total = SACNSender.packetBytes
        var p = [UInt8](repeating: 0, count: total)

        // ---- Root layer ----
        putU16(&p, 0, 0x0010)                       // Preamble Size
        putU16(&p, 2, 0x0000)                       // Post-amble Size
        let acn: [UInt8] = [0x41,0x53,0x43,0x2d,0x45,0x31,0x2e,0x31,0x37,0x00,0x00,0x00] // "ASC-E1.17"
        for i in 0..<12 { p[4 + i] = acn[i] }
        putU16(&p, 16, flagsLen(total - 16))        // Root flags+length (622)
        putU32(&p, 18, 0x0000_0004)                 // VECTOR_ROOT_E131_DATA
        for i in 0..<16 { p[22 + i] = cid[i] }       // CID

        // ---- Framing layer ----
        putU16(&p, 38, flagsLen(total - 38))        // Framing flags+length (600)
        putU32(&p, 40, 0x0000_0002)                 // VECTOR_E131_DATA_PACKET
        for i in 0..<64 { p[44 + i] = sourceName64[i] } // Source Name
        p[108] = 100                                // Priority (default)
        // 109..110 Synchronization Address = 0
        p[111] = sequence                           // Sequence Number
        p[112] = options                            // Options
        putU16(&p, 113, UInt16(universe))           // Universe

        // ---- DMP layer ----
        putU16(&p, 115, flagsLen(total - 115))      // DMP flags+length (523)
        p[117] = 0x02                               // VECTOR_DMP_SET_PROPERTY
        p[118] = 0xa1                               // Address Type & Data Type
        // 119..120 First Property Address = 0x0000
        putU16(&p, 121, 0x0001)                     // Address Increment
        putU16(&p, 123, UInt16(SACNSender.slotCount + 1)) // Property Value Count (513)
        // 125 START Code = 0x00 (Null START)
        for i in 0..<SACNSender.slotCount {
            p[126 + i] = i < slots.count ? slots[i] : 0
        }
        return p
    }

    /// 0x7000 | (12-bit PDU octet count).
    @inline(__always) private func flagsLen(_ len: Int) -> UInt16 { 0x7000 | (UInt16(len) & 0x0FFF) }

    @inline(__always) private func putU16(_ p: inout [UInt8], _ off: Int, _ v: UInt16) {
        p[off] = UInt8(v >> 8); p[off + 1] = UInt8(v & 0xFF)
    }
    @inline(__always) private func putU32(_ p: inout [UInt8], _ off: Int, _ v: UInt32) {
        p[off] = UInt8((v >> 24) & 0xFF); p[off + 1] = UInt8((v >> 16) & 0xFF)
        p[off + 2] = UInt8((v >> 8) & 0xFF); p[off + 3] = UInt8(v & 0xFF)
    }

    // MARK: Destination address

    private func destination(for universe: Int) -> sockaddr_in? {
        let ipString: String
        switch mode {
        case .unicast:
            guard !unicastHost.isEmpty else { onLog("sACN: unicast mode but no host configured"); return nil }
            ipString = unicastHost
        case .multicast:
            ipString = "239.255.\((universe >> 8) & 0xFF).\(universe & 0xFF)"
        }
        guard let inaddr = ipv4(ipString) else { onLog("sACN: bad destination \(ipString)"); return nil }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = inaddr
        return addr
    }

    /// Parse a dotted-quad IPv4 string into a network-order in_addr.
    private func ipv4(_ s: String) -> in_addr? {
        var addr = in_addr()
        let rc = s.withCString { inet_pton(AF_INET, $0, &addr) }
        return rc == 1 ? addr : nil
    }

    /// Resolve an interface spec — a full dotted-quad IP, an interface name ("en14"), or a subnet
    /// prefix ("192.168.202") — to a concrete local IPv4 + a label for logging. nil if no NIC matches.
    private static func resolveInterface(_ spec: String) -> (addr: in_addr, label: String)? {
        // A full dotted-quad? bind it directly.
        var literal = in_addr()
        if spec.withCString({ inet_pton(AF_INET, $0, &literal) }) == 1 {
            return (literal, "\(spec) (literal)")
        }
        // Otherwise scan the live interfaces for a name / subnet-prefix match.
        let prefix = spec.hasSuffix(".") ? spec : spec + "."
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return nil }
        defer { freeifaddrs(ifap) }
        var ptr = ifap
        while let p = ptr {
            let ifa = p.pointee
            ptr = ifa.ifa_next
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            var a = sockaddr_in()
            memcpy(&a, sa, Int(MemoryLayout<sockaddr_in>.size))
            let ip = String(cString: inet_ntoa(a.sin_addr))
            if name == spec || ip == spec || ip.hasPrefix(prefix) {
                return (a.sin_addr, "\(ip) (\(name))")
            }
        }
        return nil
    }

    /// "en0=192.168.26.7, en14=192.168.202.102, …" — for a helpful log when the spec doesn't match.
    private static func availableIPv4Interfaces() -> String {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return "(none)" }
        defer { freeifaddrs(ifap) }
        var parts: [String] = []
        var ptr = ifap
        while let p = ptr {
            let ifa = p.pointee
            ptr = ifa.ifa_next
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var a = sockaddr_in()
            memcpy(&a, sa, Int(MemoryLayout<sockaddr_in>.size))
            let ip = String(cString: inet_ntoa(a.sin_addr))
            if ip == "127.0.0.1" { continue }
            parts.append("\(String(cString: ifa.ifa_name))=\(ip)")
        }
        return parts.isEmpty ? "(none)" : parts.joined(separator: ", ")
    }

    // MARK: Test hook

    /// Build a packet without sending — used by the self-test to validate the byte layout.
    public func debugBuildPacket(universe: Int, slots: [UInt8]) -> [UInt8] {
        buildPacket(universe: universe, slots: slots, sequence: 0, options: 0)
    }

    public static var fullPacketSize: Int { packetBytes }
}
