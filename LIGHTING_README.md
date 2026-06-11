# Lighting — ShowRunner lighting module

A **separate, self-contained** lighting engine bolted onto ShowRunner. It drives the venue's rig
over **sACN (E1.31)** — sequenced to the audio for the EDM pieces, cue-advanced for the quiet
pieces — and ships with an **abstract stage preview** so you can verify colour and scale at home
before the rig exists. Built for the Zaventem concert (CC De Factorij, Thu 11 June 2026).

> **The patch is now the FINAL venue plot** — `Lighting_Plot/Lions patchv01.pdf` + `Lions v01.pdf`
> ("Lions v01", Bruno Peysmans, 11/6/2026): **8 × Robe Spiider (Mode 3, 33ch)** + **2 × Robe T1
> Profile (Mode 3, 53ch)** on universe 2, **7 × Robert Juliat Dalis 860 MKII (Mode 2, 22ch)** as a
> cyc row on universe 3, and the venue's **23 × 2 kW front-catwalk dimmers** (one "FrontWash"
> level) on universe 1. There are **no Fargos** in the final plot. Old rig files are in
> `backup/lighting-rig-v1/`.

> **Maximum modularity / the audio show is never at risk.** Every line of lighting lives in its own
> Swift module (`ShowRunnerApp/Sources/Lighting/`) and its own windows. It talks to the audio app
> through a single read-only `ShowClock` protocol — it *reads* the playback position the audio
> engine already publishes and **writes nothing back**. `AudioEngine.swift` and every other audio/UI
> file is **byte-for-byte unchanged**. If lighting is disabled or fails for any reason, the audio
> show runs exactly as before.

---

## Contents
1. [How it connects (and why it can't break audio)](#how-it-connects)
2. [Quick start](#quick-start)
3. [The two windows](#the-two-windows)
4. [Abstract stage preview](#abstract-stage-preview)
5. [Build-order status](#build-order-status)
6. [Venue reconciliation](#venue-reconciliation)
7. [Fixture profiles & verified channel maps](#fixture-profiles)
8. [⚠️ On-the-day CONFIRM checklist](#confirm-checklist)
9. [sACN / network](#sacn--network)
10. [Config reference (`lighting.json`)](#config-reference)
11. [EDM timelines (data, not code)](#edm-timelines)
12. [Controls reference](#controls-reference)
13. [Build / run / test commands](#commands)
14. [File map](#file-map)
15. [What's staged next](#whats-next)

---

<a name="how-it-connects"></a>
## 1. How it connects (and why it can't break audio)

```
  AudioEngine (UNCHANGED)
        │  elapsedSeconds / isPlaying   ← read-only
        ▼
  AudioShowClock  ──(ShowClock protocol)──►  Lighting module
        ▲                                     • config + fixture profiles
  AppController.go()/stop()  ──pieceDidStart/allStop──►  • sACN sender (UDP)
   (4 guarded, additive lines)                           • 40 fps renderer (own queue)
                                                          • Lighting window + Stage preview
```

- The lighting render loop runs on its **own high-priority background queue** — never the main
  thread, never the audio real-time thread. A slow frame or a wedged NIC cannot glitch audio or
  freeze the operator UI (the sACN socket also has a 50 ms send timeout).
- Reading the clock is a lock-free read of a value the audio UI already reads 10×/second.
- `LightingController` init is **fail-safe**: a missing/broken `lighting.json` falls back to the
  brief's provisional defaults; it never throws into the show. Disabled → the bridge is `nil`.
- The only host edits are ~15 additive lines: `lighting?.…` calls in `AppController`, a
  `--lighting-selftest`/`--lighting-preview` branch in `main.swift`, the `Lighting` target in
  `Package.swift`, and a fail-safe `LightingBridge.swift`.

---

<a name="quick-start"></a>
## 2. Quick start

```bash
cd "ShowRunnerApp" && ./build.sh        # rebuilds ShowRunner.app (now links the Lighting module)
open "../ShowRunner.app"                # launches the show — two extra windows appear for lighting
```

On launch you get the audio operator window **plus** a **Lighting** control window and a **Stage
Preview** window (top-left). Lighting starts sending sACN at 40 fps immediately. Fire pieces from
the audio window exactly as before — lighting follows automatically.

**First lighting test on the day:** press **PROOF OF LIFE** in the Lighting window → Dalis 4 (the
first cyc batten, universe 3 addr 67) should ramp to full white and fade. Nothing else proceeds
until a fixture obeys this.

---

<a name="the-two-windows"></a>
## 3. The two windows

**Lighting (control).** Status line (SENDING / universes), current piece + mode, cue/position, and
buttons:
- **BLACKOUT** — instant kill of all output; latches until you tap it again or fire the next piece.
- **HOLD** — freeze the current look (safety net if timecode drifts).
- **PROOF OF LIFE** — Dalis 4 to white, then fade (the soundcheck test).
- **◀ PREV CUE / NEXT CUE ▶** — advance the 2–3 cues on SOLO/TRIO pieces.
- **ARM MOVERS** — enable the provisional Spiider/T1 output once their patched mode is confirmed.
- **STAGE PREVIEW** — re-open the preview window if you closed it.
- A live **VENUE CONFIRM CHECKLIST**.

**Stage Preview (abstract).** See below.

---

<a name="abstract-stage-preview"></a>
## 4. Abstract stage preview

A deliberately **non-photoreal** front-of-house cartoon so you can verify **colour** and **scale**
without the rig. It reads the same per-frame look the engine computes and paints:

- **Cyclorama wash** (back wall) — blended colour of the seven **Dalis** battens × intensity.
- **Front wash band** — the 23 catwalk dimmers as one warm-white apron glow × the FrontWash level.
- **Aerial beams** — the **Spiiders** (and the two **T1s**, drawn narrower) as translucent cones
  from the top, positioned per the plot; **direction follows pan/tilt, width follows zoom**, plus
  a landing pool. The pairs read mirrored.
- **Fixture markers + labels.** A fixture that is **not emitting live** (blackout, or a provisional
  mover that hasn't been armed) is still drawn in its *intended* colour (so you can judge the
  design) but ringed with an **orange dashed "preview / not live"** marker.

It is a pure reader on the main thread — it never touches the engine or audio.

**Headless PNG export** (no windows needed — handy for remote checks / docs):
```bash
"../ShowRunner.app/Contents/MacOS/ShowRunner" --lighting-preview out.png <pieceOrder> <seconds>
# e.g. Torrent drop 1:          --lighting-preview drop1.png 6 53
#      Torrent drop 2:          --lighting-preview drop2.png 6 112
#      the piano interlude:     --lighting-preview interlude.png 6 80
#      a SOLO piece:            --lighting-preview solo.png 1 0
# (piece numbers = the `order` strings in showrunner.json — Torrent is piece 6
#  in the 20-cue running order)
```

> Caveat: the preview approximates colour mixing and beam geometry abstractly. It is for judging
> palette and rough coverage, **not** photometric accuracy — the real look is verified on the rig.

---

<a name="build-order-status"></a>
## 5. Build-order status (per the brief)

| Step | Item | Status |
|---|---|---|
| 1 | Config with all CONFIRM values + fixture profiles | ✅ `lighting.json` + `Sources/Lighting/Profiles/` (FINAL plot patch) |
| 2 | sACN output layer | ✅ `SACNSender.swift` (native E1.31, byte-verified) |
| 3 | **PROOF OF LIFE** — one fixture to white, then fade | ✅ Lighting window button (targets Dalis 4) |
| 4 | Master clock + per-frame renderer (40 fps) | ✅ `Renderer.swift` |
| 5 | One EDM piece end-to-end (reference) | ✅ `Timelines/torrent.json` — re-authored for the final rig with section times from band-split energy analysis of the actual backing track |
| 6 | Clone to the other EDM pieces | ✅ furelise (7), canon (8), moonlight (9), fourseasons (13), stilldre (E3) — all from per-track audio analysis |
| 7 | SOLO/TRIO templates instantiated per piece | ✅ `Templates.swift` + `lighting.json` |
| 8 | Global blackout + manual override | ✅ Lighting window |
| — | Abstract stage preview (extra) | ✅ `LightingVisualizerWindow.swift` |

---

<a name="venue-reconciliation"></a>
## 6. The FINAL venue plot (CC De Factorij, Theaterzaal Maupertuis)

Source of truth: **`Lighting_Plot/Lions patchv01.pdf`** (patch) + **`Lions v01.pdf`** (drawing,
"Lions v01", Bruno Peysmans, 11/6/2026). The full patch:

| Universe | Addr | Fixture | Our name |
|---|---|---|---|
| 1 | 2–24 | 23 × 2 kW Profile/PC, front catwalk (1-ch dimmers) | `FrontWash` (one level) |
| 1 | 501–506 | House lights (doors/stairs/parterre/balcony) | not patched — venue |
| 1 | 509–512 | MDG ATMe hazer (heater/pressure/fog/fan) | not patched — agree haze with venue |
| 2 | 1, 41, 81, 121, 161, 201, 241, 281 | 8 × Robe Spiider, **Mode 3, 33ch** | `Spiider1`…`Spiider8` |
| 2 | 321, 381 | 2 × Robe T1 Profile, **Mode 3, 53ch** | `T1L`, `T1R` |
| 3 | 67, 89, 111, 133, 155, 177, 199 | 7 × RJ Dalis 860 MKII, **Mode 2, 22ch** | `Dalis4`…`Dalis10` |

Positions (plot top view): Spiider 1/2 = downstage pair ±2 m; 3/4 and 5/6 = wide pairs ±7 m on two
battens; 7/8 = upstage inner pair ±3 m; T1s upstage-centre (back-key specials over the piano);
Dalis 4–10 one even row washing the cyc. Mirrored pairs 1↔2, 3↔4, 5↔6, 7↔8.

Network (plot page 1): light network **192.168.202.0/24, DHCP, default protocol sACN**.

---

<a name="fixture-profiles"></a>
## 7. Fixture profiles & verified channel maps

Each profile translates semantic values (`intensity`, `red/green/blue/white`, `pan/tilt`, `zoom`,
`strobe`, all 0…1) into raw DMX for its mode. **All venue-dependent values are isolated to one table
per profile**, so a mode change is a one-file edit — no cue/timeline changes.

### Robe Spiider — `SpiiderMode3Profile.swift` — **verified map, provisional arming**
Mode 3 "Advanced" (33ch), offsets **from the official Robe chart v2.3**: pan/tilt 16-bit at 1–4,
global RGBW 16-bit at 8–15, zoom 16-bit at 29–30 (**inverted: DMX 0 = widest**, the profile writes
`1 − zoom`), **shutter 31** (`0–31 = CLOSED`, `32 = open`, `64–95 = strobe`), dimmer 16-bit 32–33.
Ch 6 (Power/Special) deliberately 0; virtual colour wheel, CTC, pixel effects and the flower
effect all parked off. Dark until **ARM MOVERS**.

### Robe T1 Profile — `T1Mode3Profile.swift` — **verified map, provisional arming**
Mode 3 "Five colours" (53ch), **from the official Robe chart v2.1**: the five raw emitters
R/G/B/Amber/Lime, 16-bit, at 12–21 (`white` lifts all five = chart open white); zoom 16-bit 38–39
(inverted); focus 40 parked 128; shutter 51 (32 = open, 64–95 strobe); dimmer 16-bit 52–53.
Non-zero park values matter here: **CTO 22 = 110 (5600 K — 0 would be 8000 K!)**, green correction
23 = 128, all rotation channels 128, framing blades out. Dark until **ARM MOVERS**.

### Robert Juliat Dalis 860 MKII — `DalisMode2Profile.swift` — **live**
Mode 2 "Full 1 group mode 16b" (22ch), **from the official RJ manual DN41077600-B**: 16-bit dimmer
at 1–2, then all 8 emitters 16-bit (R 3, G 5, B 7, Royal blue 9, Cyan 11, Amber 13, Cool white 15,
Warm white 17 — `white` drives Cool white), strobe duration 19 (0 = off), response-time 21 = 255
(OFF, so the app's fades aren't double-smoothed). `isProvisional = false` — the plot's "Mode 2
22ch" matches the manual exactly and a cyc batten can't misbehave; it's also the PROOF OF LIFE
target. Sanity-check colours at soundcheck.

### Front catwalk — `FrontWashProfile.swift` — **live**
The venue's 23 × 2 kW front-catwalk dimmers (universe 1, addr 2–24) as ONE submaster-style level:
`intensity` writes the same byte to all 23 channels. This is what keeps the pianist lit.

**Safety:** the renderer **skips provisional profiles entirely until armed** — Spiiders/T1s can
never emit garbage before their patched mode is confirmed.

---

<a name="confirm-checklist"></a>
## 8. ⚠️ On-the-day CONFIRM checklist

Each item is a one-place edit — no cue/show-logic changes. The patch itself is now the venue's
own plot, so the day-of checks are about *reality matching the paper*:

1. **PROOF OF LIFE** — Dalis 4 to white and fade. Nothing proceeds until this works.
2. **Spiider mode** — confirm the units are *patched* in **Mode 3 (33ch)** and **RGBW mixing** is
   active (else R/G/B/W read as C/M/Y). If a different mode is set, re-pull that column into
   `SpiiderMode3Profile.swift`. Then **ARM MOVERS**.
3. **T1 mode** — confirm **Mode 3 (53ch)**. Check one T1 makes a clean neutral open white (if it
   looks blue, the CTO park value needs attention). Covered by the same **ARM MOVERS** switch.
4. **Dalis colours** — already live; bring up a piece and check the cyc shows the intended colour
   (Mode 2, 22ch, 16-bit).
5. **Front wash** — `FrontWash` at ~0.5 should light the piano evenly; ask the venue which catwalk
   units are focused where (we drive all 23 as one level).
6. **Network** — plug into the venue light network (192.168.202.0/24, DHCP, sACN). `lighting.json →
   network.mode` is `multicast`; switch to `unicast` + a node IP only if the venue prefers. On a
   Mac with Ethernet + Wi-Fi, pin the interface so sACN leaves via the lighting LAN.
7. **Haze** — agree a steady low haze level with the venue tech (MDG ATMe is on their universe 1);
   the EDM beam looks want it.

The Lighting window shows this checklist live, and every CONFIRM value is logged at startup.

---

<a name="sacn--network"></a>
## 9. sACN / network

Native ANSI E1.31-2016 DATA packets over UDP, no third-party deps. A full 512-slot packet is
**638 bytes** (verified byte-for-byte against the standard + reference implementations). Multi-byte
fields big-endian; per-universe sequence counter; priority 100; multicast group
`239.255.<universe-hi>.<universe-lo>` on UDP **5568**; on stop, 3 Stream_Terminated packets are sent.
Output target is config (multicast default, or unicast to a node IP).

---

<a name="config-reference"></a>
## 10. Config reference — `lighting.json` (at the show root)

Read at launch; editing it never touches the audio show. Keys starting with `_` are notes (ignored).

```jsonc
{
  "enabled": true,                 // false = lighting fully off; audio unaffected
  "frameRateHz": 40,
  "network": { "mode": "multicast", "unicastHost": "", "port": 5568,
               "sourceName": "ShowRunner Lighting", "cid": "<stable-UUID>" },
  "universes": { "front": 1, "movers": 2, "dalis": 3 },   // per the venue patch sheet
  "fixtures": [ { "name": "Spiider1", "profile": "spiider_mode3", "universe": "movers", "address": 1 } ],
  // profiles: "spiider_mode3" | "t1_mode3" | "dalis_mode2" | "front_wash"
  "pieces": {
    "1":  { "template": "solo", "cycColor": [0.10, 0.10, 0.45], "intensity": 0.85 },
    "4":  { "template": "edm",  "timeline": "Timelines/torrent.json" }
    // template: "solo" | "trio" | "edm" | "off"
  }
}
```

If `lighting.json` is missing or partial, the module falls back to the brief's provisional rig — it
never crashes. The rig also **warns on overlapping DMX addresses or unknown universe roles** (common
show-day mis-patches).

### The piano anchor — `stage` (last-minute "point the rig at the piano" knob)

This is a piano show, so the **whole mover rig is parametrised on where the piano sits**. Instead of
re-aiming eight Spiiders + two T1s across every timeline by hand, edit ONE block in `lighting.json`:

```jsonc
"stage": { "pianoPan": 0.46, "pianoTilt": 0.40, "stretch": 1.0 }
```

- **`pianoPan` / `pianoTilt`** (0…1, 0.5 = stage centre) — the **root**: where the piano is. The plot
  puts it centre, slightly left, so `pianoPan` defaults just under 0.5. **If the piano moves on the
  day, change these two numbers — nothing else.**
- **`stretch`** — one gain on how far every mover's aim deviates from that root:
  `finalAim = root + (authoredAim − root) × stretch`, clamped 0…1.
  - `1.0` = **identity** — the authored timelines/cues play exactly as designed (the safe default).
  - `< 1` pulls the whole rig **in toward the piano**; `0` = every beam lands on the piano.
  - `> 1` exaggerates the spread (beams fan wider than authored).

**Scope:** aim (pan/tilt) only — colour, intensity, zoom and the non-movers (FrontWash, Dalis) are
never touched. It applies to all movers (Spiiders + T1s).

**How to make a last-minute adjustment (no recompile, no code):**
1. Edit the `stage` block in `lighting.json` (it's plain config, read at launch).
2. Preview without the rig: `"../ShowRunner.app/Contents/MacOS/ShowRunner" --lighting-preview out.png 6 50.9`
   (Torrent drop 1 — a wide-fan moment, so the effect is obvious). Lower `stretch`, re-export, compare.
3. Relaunch the app (or it picks it up on next launch). The live rig **and** the preview focal point
   both follow — they share the same transform.

**Where the logic lives (don't rewrite it):** the transform is `Rig.applyStageAnchor(_:)` in
`Sources/Lighting/Rig.swift`, called once per frame from `Renderer.tick()` (after `computeFrame`, so
cue tracking stays in authored space) and once in `LightingPreview.renderPNG`. The config plumbing is
`LightingConfig.StageAnchor` in `Sources/Lighting/LightingConfig.swift`. **For a show-day tweak you
should only ever need to touch the three numbers in `lighting.json` — leave the Swift alone.**

---

<a name="edm-timelines"></a>
## 11. EDM timelines (data, not code) — `Timelines/*.json`

Each EDM piece's lighting is a keyframe timeline mapped to **seconds** — editable/retimeable without
recompiling. A keyframe sets sparse semantic values (omitted fields default; `pan/tilt` default 0.5
= centre — mover tracks restate colour+pan+tilt+zoom in every keyframe for this reason); `ease` is
`hold`, `linear`, or `smooth`. Fixture tokens: `Spiiders`, `T1s`, `Dalis`, `Front`, `All`, a single
name, or a **"+"-joined list** (`"Spiider3+Spiider5"`) to drive a side stack from one track.
Mirrored pairs are authored with right pan = 1 − left pan.

```jsonc
{ "piece": "6", "template": "edm", "durationSeconds": 149,
  "tracks": [
    { "fixture": "Spiider3+Spiider5", "keyframes": [
        { "t": 50.9, "ease": "hold", "state": { "red": 0.95, "blue": 0.45, "intensity": 1.0,
                                                 "pan": 0.85, "tilt": 0.25, "zoom": 0.9, "strobe": 0.6 } }
    ] } ] }
```

`SoloTemplate` / `TrioTemplate` build reusable cue lists from a `cycColor` + `intensity`;
`EDMTemplate` can synthesize a timeline from section markers (intro/build/drop/breakdown/outro) for
cloning the reference piece. **`Timelines/torrent.json` (piece 6, Torrent) is authored for the final rig**,
with section times measured from the backing track (music in 2.9 s · drop 1 at 50.9 s · cut 76.5 s
· piano interlude · cut 98.4 s · drop 2 at 109.5 s · cut 134.6 s · final climax 137.4–141.5 s ·
out by 148.5 s). The other EDM pieces fall back to a clearly-labelled **NEUTRAL WASH (no
timeline)** and log a note.

---

<a name="controls-reference"></a>
## 12. Controls reference

| Control | Where | Effect |
|---|---|---|
| **GO / STOP** | audio window (Space / Esc) | STOP **instantly hard-cuts** lighting (matches the audio panic); cleared on the next GO |
| **BLACKOUT** | Lighting window | instant kill latch |
| **HOLD** | Lighting window | freeze current look |
| **PROOF OF LIFE** | Lighting window | Dalis 4 white → fade |
| **PREV / NEXT CUE** | Lighting window | advance SOLO/TRIO cues |
| **ARM MOVERS** | Lighting window | enable Spiiders/T1s once their patched mode is confirmed |
| **STAGE PREVIEW** | Lighting window | re-open the preview window |

---

<a name="commands"></a>
## 13. Build / run / test commands

```bash
cd "ShowRunnerApp"
./build.sh                                   # rebuild ShowRunner.app (links Lighting)
swift run -c release ShowRunner              # dev run

# Headless checks (no rig / no network needed):
"../ShowRunner.app/Contents/MacOS/ShowRunner" --lighting-selftest          # validates sACN packet + config + profiles
"../ShowRunner.app/Contents/MacOS/ShowRunner" --lighting-preview out.png 4 42   # export an abstract look
```

The audio `--selftest` is unchanged.

---

<a name="file-map"></a>
## 14. File map — `ShowRunnerApp/Sources/Lighting/`

| File | Role |
|---|---|
| `ShowClock.swift` | the one read-only contract with the host |
| `LightingConfig.swift` | `lighting.json` loader + provisional defaults (all CONFIRM values) |
| `FixtureProfile.swift` | `FixtureState`, profile protocol, registry |
| `Profiles/SpiiderMode3Profile.swift` | Spiider Mode 3 33ch (verified, provisional arming) |
| `Profiles/T1Mode3Profile.swift` | T1 Profile Mode 3 53ch (verified, provisional arming) |
| `Profiles/DalisMode2Profile.swift` | Dalis Mode 2 22ch (verified, live) |
| `Profiles/FrontWashProfile.swift` | front catwalk, 23 × 1-ch dimmers as one level (live) |
| `DMXUniverse.swift` | 512-slot frame + DMX byte helpers |
| `SACNSender.swift` | native E1.31 UDP sender (thread-safe, 50 ms send timeout) |
| `Rig.swift` | fixtures → universes; group tokens; mis-patch warnings |
| `Timeline.swift` | Codable keyframe timeline + sampling |
| `CueList.swift` / `Templates.swift` | cue model + SOLO/TRIO/EDM templates |
| `Renderer.swift` | 40 fps loop; timecode + cue modes; blackout/hold/proof; status + visual snapshots |
| `LightingController.swift` | top-level: owns config/rig/sender/renderer/windows |
| `LightingWindow.swift` | the control window |
| `LightingVisualizerWindow.swift` | the abstract stage preview |
| `LightingPreview.swift` | headless PNG export of a look |
| `LightingSelfTest.swift` | packet/config/profile validation |

Host glue lives in `Sources/ShowRunner/LightingBridge.swift` (+ a few additive lines in
`AppController.swift` / `main.swift`).

---

<a name="whats-next"></a>
## 15. What's staged next

All show timelines are authored: the six EDM pieces (torrent 6, furelise 7, canon 8,
moonlight 9, fourseasons 13, stilldre E3 — each from per-track audio analysis, all sharing
torrent.json's 10-track structure) plus self-driven looping `auto` timelines for the live
piano pieces. Remaining work is on the rig itself: the §8 on-the-day checklist, then taste
passes (retime/recolour the JSON — no recompiling) once the looks are visible on real
fixtures. For any new piece: clone the torrent.json track structure, measure the audio
(see `VENUE_LIGHTING_REFERENCE.md` §6), preview with `--lighting-preview <piece> <seconds>`.
