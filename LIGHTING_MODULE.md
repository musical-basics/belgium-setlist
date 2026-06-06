# Lighting module

A **separate, self-contained** lighting feature bolted onto ShowRunner. It drives the 8-fixture
DMX rig over **sACN (E1.31)**, sequenced to the audio for the EDM pieces and cue-advanced for the
quiet pieces. Built for the Zaventem concert (Thu 11 June 2026).

> **Maximum modularity / the audio show is never at risk.** All lighting code lives in its own
> Swift module (`Sources/Lighting/`) and its own window. It talks to the audio app through a single
> read-only `ShowClock` protocol — it reads the playback position the audio engine already
> publishes and **writes nothing back**. `AudioEngine.swift` and every other audio/UI file is
> **byte-for-byte unchanged**. If lighting is disabled or fails for any reason, the audio show runs
> exactly as before. (The only host edits are ~15 lines of additive glue in `AppController`,
> `main.swift`, and `Package.swift`.)

---

## How it connects (and why it can't break audio)

```
  AudioEngine (UNCHANGED)
        │  elapsedSeconds / isPlaying   ← read-only
        ▼
  AudioShowClock  ──(ShowClock protocol)──►  Lighting module
        ▲                                     • config + fixture profiles
  AppController.go()/stop()  ──pieceDidStart/allStop──►  • sACN sender (UDP)
   (4 guarded, additive lines)                           • 40 fps renderer (own queue)
                                                          • Lighting window
```

- Lighting runs its render loop on its **own high-priority background queue** — never the main
  thread, never the audio real-time thread. A slow frame or a socket hiccup cannot glitch audio
  or stall the UI.
- Reading the clock is a lock-free read of a value the audio UI already reads 10×/second.
- `LightingController` init is **fail-safe**: a missing/broken `lighting.json` falls back to the
  brief's provisional defaults; it never throws into the show.

---

## Build-order status (per the brief)

| Step | Item | Status |
|---|---|---|
| 1 | Config file with all CONFIRM values + fixture profiles | ✅ `lighting.json` + `Sources/Lighting/Profiles/` |
| 2 | sACN output layer | ✅ `SACNSender.swift` (native E1.31, byte-verified) |
| 3 | **PROOF OF LIFE** — one Fargo to white, then fade | ✅ button in the Lighting window |
| 4 | Master clock + per-frame renderer | ✅ `Renderer.swift` (40 fps, reads playback position) |
| 5 | One EDM piece end-to-end (reference) | ◐ `Timelines/torrent.json` authored as a worked example — **times are placeholders, tune on the rig** |
| 6 | Clone to the other 4 EDM pieces | ⬜ **staged** — needs per-track audio analysis (canon / moonlight / furelise / stilldre) |
| 7 | SOLO/TRIO templates instantiated per piece | ✅ `Templates.swift` + `lighting.json` `pieces` |
| 8 | Global blackout + manual override | ✅ Lighting window (BLACKOUT / HOLD / cue advance) |

---

## Venue reconciliation (CC De Factorij technical rider, Maupertuis hall)

The rider's intelligent-light list **matches the rig** — every fixture our code drives is present:

| Our code | Venue rider (page 8) | Have / use |
|---|---|---|
| Spiider (`spiider_mode2`) | **12 × Robe Spiider** | 12 / 2 |
| Fargo (`fargo_9ch`) | **28 × Fargo Stagepar 19 Pro Zoom MKII** | 28 / 4 |
| Dalis (`dalis_stub`) | **14 × Robert Juliat 860 Dalis MKII** | 14 / 2 |

(Confirms the earlier name questions: "Fargo" is the *Fargo-brand StagePar 19 Pro Zoom MKII*, and
"Dalis" is *Robert Juliat 860 Dalis MKII* — not Robe.) The rider also confirms the transport is
**sACN**: "8 looms DMX/power in the ceiling, 10 DMX ports on the floor, **each assignable to
whatever universe**" — so our universe numbers are ours to pick; just coordinate which physical
ports carry them. Unused-but-available: 8 × Robe Robin Viva CMY, 9 × Showtec LED Bar.

## ⚠️ VENUE CONFIRM checklist (do these on the day)

Everything below is isolated so each is a **one-place edit** — no cue or show-logic changes.

1. **Spiider mode** — the **Mode 2 "Basic" (27ch) map is now filled and verified** against the
   official Robe chart v2.3 (`SpiiderMode2Profile.swift`). It stays `isProvisional` only because the
   *fixture's patched mode* is an on-the-day choice: **confirm the Spiider is set to Mode 2**, then
   **ARM MOVERS**. If it's in Mode 1/3/4 instead, re-pull that column. Also confirm **RGBW mixing**
   is active (else R/G/B/W read as C/M/Y). *Until armed, the Spiiders stay dark.*
   Chart: `https://www.robe.cz/res/downloads/dmx_charts/Robin_SPIIDER_DMX_charts.pdf`
2. **Dalis** — **Robert Juliat 860 Dalis MKII**. `DalisStubProfile.swift` now implements **Mode 3
   "Full 1 group 8b" (13ch)**, verified from the official RJ manual. Stays provisional: confirm the
   MKII unit reports 13ch in Mode 3 (`SETUP ▸ DMX ▸ PERSONALITY`), patch it, then **ARM MOVERS**.
3. **sACN universe numbers** — `lighting.json → universes`. Pick them and tell the venue tech which
   DMX ports should carry universe 1 (Spiiders) and universe 2 (Fargo/Dalis).
4. **Network target** — `lighting.json → network.mode`: `multicast` (onto the venue's sACN lighting
   LAN, 239.255.x.x) or `unicast` (set `unicastHost` to a node's IP). On a Mac with both Ethernet
   and Wi-Fi, prefer unicast or pin the interface so sACN leaves via the lighting LAN.
5. **Fargo channel order** — the brief's order (R,G,B,W,Dim,DimFine,Strobe,Color,Zoom) for the
   Stagepar 19 Pro Zoom MKII. **Verify on the day** against the fixture's own DMX chart; if
   different, edit only the `Ch` table in `FargoProfile.swift`.

---

## On the day — first lighting test (soundcheck)

1. Patch the rig, set each fixture's DMX address and mode to match `lighting.json` / the profiles.
2. Launch ShowRunner. The **Lighting** window opens top-left (separate from the audio window).
3. Confirm the status line says **SENDING · universes 1,2**.
4. Hit **PROOF OF LIFE** → Fargo 1 should ramp to full white and fade. *Nothing else proceeds
   until a fixture obeys this.* If it doesn't: check the network target (#4 above), cabling, and
   the fixture's address/mode.
5. Confirm the venue's Spiider mode, update the profile, rebuild, **ARM MOVERS**.
6. Fire each EDM piece and tune its timeline (see below) against the audio.

`BLACKOUT` kills all output instantly (and keeps the rig dark). `HOLD` freezes the current look if
timecode drifts. For SOLO/TRIO pieces, advance the 2–3 cues with **NEXT CUE**.

---

## Editing the show (data, not code)

- **Per-piece lighting** is in `lighting.json → pieces` (keyed by the piece `order`). SOLO/TRIO
  carry a `cycColor` + `intensity`; EDM points at a timeline file.
- **EDM timelines** live in `Timelines/*.json` as keyframes mapped to seconds — edit/retime
  without recompiling. Each keyframe sets semantic values (`intensity`, `red/green/blue/white`,
  `pan/tilt`, `zoom`, `strobe`), all 0…1; omitted fields use defaults. `ease` is `hold`,
  `linear`, or `smooth`. Fixture tokens: `Fargos`, `Spiiders`, `Dalis`, `All`, or a single name
  (`Fargo1`, `Spiider1`…). The two Spiiders move mirrored (Spiider2 pan = 1 − Spiider1 pan).
- Only `Timelines/torrent.json` (piece 4) is authored as a reference. The other four EDM
  pieces reference files that don't exist yet, so they fall back to a safe neutral wash and log a
  note — author them next (clone the torrent structure, set section times from each track).

## Run / test

```bash
cd "ShowRunnerApp" && ./build.sh        # rebuild ShowRunner.app (now links the Lighting module)
"../ShowRunner.app/Contents/MacOS/ShowRunner" --lighting-selftest   # validates sACN packet + config
```

`--lighting-selftest` is headless (no network/fixtures needed): it checks the E1.31 packet is
byte-exact, the config loads, fixtures resolve, and the Fargo profile renders correctly. The audio
`--selftest` is unchanged.
