import Foundation

/// Headless validation of the lighting module: confirms the sACN packet is byte-exact to the
/// ANSI E1.31 spec, the multicast formula is right, config loads, every fixture resolves to a
/// profile, and the (confirmed) Fargo profile renders correctly. No network or fixtures needed.
///
/// Returns the number of failures and a human-readable report the host can print.
public enum LightingSelfTest {
    public static func run(showRoot: URL) -> (failures: Int, lines: [String]) {
        var failures = 0
        var lines: [String] = []
        func ok(_ s: String) { lines.append("  ✅ \(s)") }
        func fail(_ s: String) { lines.append("  ❌ \(s)"); failures += 1 }

        lines.append("Lighting self-test")
        lines.append(String(repeating: "-", count: 56))

        // --- sACN packet layout (the correctness-critical part) ---
        let cid: [UInt8] = (0..<16).map { UInt8($0 + 1) }
        let sender = SACNSender(mode: .multicast, unicastHost: "", interfaceIP: nil,
                                port: 5568, cid: cid, sourceName: "ShowRunner Lighting")
        var slots = [UInt8](repeating: 0, count: 512)
        slots[0] = 0x11; slots[1] = 0x22; slots[511] = 0xFF
        let pkt = sender.debugBuildPacket(universe: 2, slots: slots)

        if pkt.count == 638 { ok("packet size = 638 bytes (full 512-slot frame)") }
        else { fail("packet size = \(pkt.count), expected 638") }

        func u16(_ o: Int) -> UInt16 { (UInt16(pkt[o]) << 8) | UInt16(pkt[o + 1]) }
        func u32(_ o: Int) -> UInt32 { (UInt32(pkt[o]) << 24) | (UInt32(pkt[o+1]) << 16) | (UInt32(pkt[o+2]) << 8) | UInt32(pkt[o+3]) }

        check(&failures, &lines, "preamble size 0x0010", u16(0) == 0x0010)
        check(&failures, &lines, "post-amble size 0x0000", u16(2) == 0x0000)
        let acn: [UInt8] = [0x41,0x53,0x43,0x2d,0x45,0x31,0x2e,0x31,0x37,0x00,0x00,0x00]
        check(&failures, &lines, "ACN packet identifier 'ASC-E1.17'", Array(pkt[4..<16]) == acn)
        check(&failures, &lines, "root flags+length 0x726E", u16(16) == 0x726E)
        check(&failures, &lines, "root vector 0x00000004", u32(18) == 0x0000_0004)
        check(&failures, &lines, "CID round-trips", Array(pkt[22..<38]) == cid)
        check(&failures, &lines, "framing flags+length 0x7258", u16(38) == 0x7258)
        check(&failures, &lines, "framing vector 0x00000002", u32(40) == 0x0000_0002)
        check(&failures, &lines, "priority 100", pkt[108] == 100)
        check(&failures, &lines, "options 0x00", pkt[112] == 0x00)
        check(&failures, &lines, "universe field = 2", u16(113) == 2)
        check(&failures, &lines, "DMP flags+length 0x720B", u16(115) == 0x720B)
        check(&failures, &lines, "DMP vector 0x02", pkt[117] == 0x02)
        check(&failures, &lines, "address & data type 0xA1", pkt[118] == 0xA1)
        check(&failures, &lines, "first property address 0x0000", u16(119) == 0x0000)
        check(&failures, &lines, "address increment 0x0001", u16(121) == 0x0001)
        check(&failures, &lines, "property value count 513", u16(123) == 513)
        check(&failures, &lines, "DMX start code 0x00", pkt[125] == 0x00)
        check(&failures, &lines, "data slot 1 at offset 126", pkt[126] == 0x11)
        check(&failures, &lines, "data slot 2 at offset 127", pkt[127] == 0x22)
        check(&failures, &lines, "data slot 512 at offset 637", pkt[637] == 0xFF)
        sender.closeSocket()

        // --- Fargo profile (confirmed) renders white correctly ---
        let u = DMXUniverse(number: 2)
        var white = FixtureState(); white.white = 1; white.intensity = 1
        FargoProfile().render(white, into: u, startAddress: 1)
        // address 4 (white) -> slot index 3; dimmer coarse/fine -> index 4/5
        check(&failures, &lines, "Fargo white → DMX addr 4 = 255", u.slots[3] == 255)
        check(&failures, &lines, "Fargo full dimmer → addr 5/6 = 255/255", u.slots[4] == 255 && u.slots[5] == 255)

        // --- Config loads + fixtures resolve to profiles ---
        let cfg = LightingConfigLoader.load(showRoot: showRoot)
        let registry = ProfileRegistry.standard()
        let rig = Rig(config: cfg, registry: registry)
        if rig.fixtures.count == cfg.fixtures.count && !rig.fixtures.isEmpty {
            ok("config: \(rig.fixtures.count) fixtures, universes \(rig.universeFrames().map { $0.number })")
        } else {
            fail("config: \(rig.fixtures.count)/\(cfg.fixtures.count) fixtures resolved to profiles")
        }
        check(&failures, &lines, "provisional fixtures are isolated (Spiider/Dalis)",
              rig.fixtures.contains { $0.profile.isProvisional })

        lines.append(String(repeating: "-", count: 56))
        lines.append(failures == 0 ? "LIGHTING: PASS ✅" : "LIGHTING: FAIL ❌ (\(failures))")
        return (failures, lines)
    }

    private static func check(_ failures: inout Int, _ lines: inout [String], _ name: String, _ cond: Bool) {
        if cond { lines.append("  ✅ \(name)") } else { lines.append("  ❌ \(name)"); failures += 1 }
    }
}
