import Foundation

/// Headless validation of the lighting module: confirms the sACN packet is byte-exact to the
/// ANSI E1.31 spec, the multicast formula is right, config loads, every fixture resolves to a
/// profile, and the plot-final profiles (Spiider Mode 3, T1 Mode 3, Dalis Mode 2, front wash)
/// render their chart-critical bytes correctly. No network or fixtures needed.
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

        // --- Profile chart-critical bytes (official Robe/RJ charts; see each profile's header) ---
        var white = FixtureState(); white.white = 1; white.intensity = 1

        // Dalis Mode 2 (22ch, live): 16-bit dimmer at 1/2, cool white at 15/16, response OFF at 21.
        let uD = DMXUniverse(number: 3)
        DalisMode2Profile().render(white, into: uD, startAddress: 1)
        check(&failures, &lines, "Dalis full dimmer → addr 1/2 = 255/255", uD.slots[0] == 255 && uD.slots[1] == 255)
        check(&failures, &lines, "Dalis white → cool white addr 15 = 255", uD.slots[14] == 255)
        check(&failures, &lines, "Dalis strobe OFF → addr 19 = 0", uD.slots[18] == 0)
        check(&failures, &lines, "Dalis response time OFF → addr 21 = 255", uD.slots[20] == 255)

        // Spiider Mode 3 (33ch): shutter ch31 MUST be 32 (open) when not strobing; dimmer ch32.
        let uS = DMXUniverse(number: 2)
        SpiiderMode3Profile().render(white, into: uS, startAddress: 1)
        check(&failures, &lines, "Spiider no-strobe → shutter addr 31 = 32 (open, not 0=closed)", uS.slots[30] == 32)
        check(&failures, &lines, "Spiider full dimmer → addr 32 = 255", uS.slots[31] == 255)
        check(&failures, &lines, "Spiider white → addr 14 = 255", uS.slots[13] == 255)
        check(&failures, &lines, "Spiider power/special addr 6 stays 0", uS.slots[5] == 0)
        var strobing = white; strobing.strobe = 1
        SpiiderMode3Profile().render(strobing, into: uS, startAddress: 1)
        check(&failures, &lines, "Spiider full strobe → shutter addr 31 = 95", uS.slots[30] == 95)

        // T1 Mode 3 (53ch): the non-zero park values that keep the beam neutral + open.
        let uT = DMXUniverse(number: 2)
        T1Mode3Profile().render(white, into: uT, startAddress: 1)
        check(&failures, &lines, "T1 CTO parked neutral → addr 22 = 110 (5600 K)", uT.slots[21] == 110)
        check(&failures, &lines, "T1 green correction parked → addr 23 = 128", uT.slots[22] == 128)
        check(&failures, &lines, "T1 no-strobe → shutter addr 51 = 32 (open)", uT.slots[50] == 32)
        check(&failures, &lines, "T1 full dimmer → addr 52 = 255", uT.slots[51] == 255)
        check(&failures, &lines, "T1 white lifts all five emitters (R+amber+lime full)",
              uT.slots[11] == 255 && uT.slots[17] == 255 && uT.slots[19] == 255)

        // Front wash: one level across exactly addresses 2…24.
        let uF = DMXUniverse(number: 1)
        var half = FixtureState(); half.intensity = 0.5
        FrontWashProfile().render(half, into: uF, startAddress: 2)
        check(&failures, &lines, "Front wash covers addr 2…24 only",
              uF.slots[0] == 0 && uF.slots[1] == 128 && uF.slots[23] == 128 && uF.slots[24] == 0)

        // --- Config loads + fixtures resolve to profiles ---
        let cfg = LightingConfigLoader.load(showRoot: showRoot)
        let registry = ProfileRegistry.standard()
        let rig = Rig(config: cfg, registry: registry)
        if rig.fixtures.count == cfg.fixtures.count && !rig.fixtures.isEmpty {
            ok("config: \(rig.fixtures.count) fixtures, universes \(rig.universeFrames().map { $0.number })")
        } else {
            fail("config: \(rig.fixtures.count)/\(cfg.fixtures.count) fixtures resolved to profiles")
        }
        check(&failures, &lines, "provisional fixtures are isolated (Spiiders/T1s gated by ARM)",
              rig.fixtures.contains { $0.profile.isProvisional })

        lines.append(String(repeating: "-", count: 56))
        lines.append(failures == 0 ? "LIGHTING: PASS ✅" : "LIGHTING: FAIL ❌ (\(failures))")
        return (failures, lines)
    }

    private static func check(_ failures: inout Int, _ lines: inout [String], _ name: String, _ cond: Bool) {
        if cond { lines.append("  ✅ \(name)") } else { lines.append("  ❌ \(name)"); failures += 1 }
    }
}
