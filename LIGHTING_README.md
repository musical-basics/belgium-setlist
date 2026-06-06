# Lighting — ShowRunner lighting module

A **separate, self-contained** lighting engine bolted onto ShowRunner. It drives the venue's
8-fixture DMX rig over **sACN (E1.31)** — sequenced to the audio for the EDM pieces, cue-advanced
for the quiet pieces — and ships with an **abstract stage preview** so you can verify colour and
scale at home before the rig exists. Built for the Zaventem concert (CC De Factorij, Thu 11 June 2026).

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

**First lighting test on the day:** press **PROOF OF LIFE** in the Lighting window → Fargo 1 should
ramp to full white and fade. Nothing else proceeds until a fixture obeys this.

---

<a name="the-two-windows"></a>
## 3. The two windows

**Lighting (control).** Status line (SENDING / universes), current piece + mode, cue/position, and
buttons:
- **BLACKOUT** — instant kill of all output; latches until you tap it again or fire the next piece.
- **HOLD** — freeze the current look (safety net if timecode drifts).
- **PROOF OF LIFE** — Fargo 1 to white, then fade (the soundcheck test).
- **◀ PREV CUE / NEXT CUE ▶** — advance the 2–3 cues on SOLO/TRIO pieces.
- **ARM MOVERS** — enable the provisional Spiider/Dalis output once their mode is confirmed.
- **STAGE PREVIEW** — re-open the preview window if you closed it.
- A live **VENUE CONFIRM CHECKLIST**.

**Stage Preview (abstract).** See below.

---

<a name="abstract-stage-preview"></a>
## 4. Abstract stage preview

A deliberately **non-photoreal** front-of-house cartoon so you can verify **colour** and **scale**
without the rig. It reads the same per-frame look the engine computes and paints:

- **Cyclorama wash** (back wall) — blended colour of the **Dalis** fixtures × intensity.
- **Front-light pools** — the **Fargos** as soft elliptical pools; **pool size grows with zoom**
  (beam width), brightness with intensity, colour from RGBW.
- **Aerial beams** — the **Spiiders** as translucent cones from the top; **direction follows
  pan/tilt, width follows zoom**, plus a landing pool. The two movers read mirrored.
- **Fixture markers + labels.** A fixture that is **not emitting live** (blackout, or a provisional
  mover that hasn't been armed) is still drawn in its *intended* colour (so you can judge the
  design) but ringed with an **orange dashed "preview / not live"** marker.

It is a pure reader on the main thread — it never touches the engine or audio.

**Headless PNG export** (no windows needed — handy for remote checks / docs):
```bash
"../ShowRunner.app/Contents/MacOS/ShowRunner" --lighting-preview out.png <pieceOrder> <seconds>
# e.g. the Torrent drop:        --lighting-preview drop.png 4 42
#      the intro:               --lighting-preview intro.png 4 5
#      a SOLO piece:            --lighting-preview solo.png 1 0
```

> Caveat: the preview approximates colour mixing and beam geometry abstractly. It is for judging
> palette and rough coverage, **not** photometric accuracy — the real look is verified on the rig.

---

<a name="build-order-status"></a>
## 5. Build-order status (per the brief)

| Step | Item | Status |
|---|---|---|
| 1 | Config with all CONFIRM values + fixture profiles | ✅ `lighting.json` + `Sources/Lighting/Profiles/` |
| 2 | sACN output layer | ✅ `SACNSender.swift` (native E1.31, byte-verified) |
| 3 | **PROOF OF LIFE** — one Fargo to white, then fade | ✅ Lighting window button |
| 4 | Master clock + per-frame renderer (40 fps) | ✅ `Renderer.swift` |
| 5 | One EDM piece end-to-end (reference) | ◐ `Timelines/torrent.json` (times are placeholders — tune on the rig) |
| 6 | Clone to the other 4 EDM pieces | ⬜ **staged** — needs per-track audio analysis |
| 7 | SOLO/TRIO templates instantiated per piece | ✅ `Templates.swift` + `lighting.json` |
| 8 | Global blackout + manual override | ✅ Lighting window |
| — | Abstract stage preview (extra) | ✅ `LightingVisualizerWindow.swift` |

---

<a name="venue-reconciliation"></a>
## 6. Venue reconciliation (CC De Factorij, Maupertuis hall)

The technical rider's intelligent-light list **matches the rig** — every fixture our code drives is
present:

| Our code | Rider (page 8) | Have / use |
|---|---|---|
| Spiider (`spiider_mode2`) | **12 × Robe Spiider** | 12 / 2 |
| Fargo (`fargo_9ch`) | **28 × Fargo Stagepar 19 Pro Zoom MKII** | 28 / 4 |
| Dalis (`dalis_stub`) | **14 × Robert Juliat 860 Dalis MKII** | 14 / 2 |

This confirmed the earlier naming questions: **"Fargo"** is the Fargo-brand *StagePar 19 Pro Zoom
MKII* (not Robe), and **"Dalis"** is *Robert Juliat 860 Dalis MKII* (not Robe). The rider also
confirms the transport is **sACN** — "8 looms DMX/power in the ceiling, 10 floor DMX ports, **each
assignable to whatever universe**" — so our universe numbers are ours to pick; just coordinate which
physical ports carry them. Unused-but-available: 8 × Robe Robin Viva CMY, 9 × Showtec LED Bar.
(Rider PDF committed at the repo root.)

---

<a name="fixture-profiles"></a>
## 7. Fixture profiles & verified channel maps

Each profile translates semantic values (`intensity`, `red/green/blue/white`, `pan/tilt`, `zoom`,
`strobe`, all 0…1) into raw DMX for its mode. **All venue-dependent values are isolated to one table
per profile**, so confirming a mode is a one-file edit — no cue/timeline changes.

### Fargo Stagepar 19 Pro Zoom MKII — `FargoProfile.swift` — **live**
9-channel, 0-based offsets: `0 R · 1 G · 2 B · 3 W · 4 Dimmer · 5 Dimmer-fine · 6 Strobe · 7 Color ·
8 Zoom`. **Order confirmed** from a Fargo-specific venue patch sheet. Value ranges (strobe window,
zoom direction) are best-guess proxies (no Fargo value chart is published) — **sweep on the day**.
If proof-of-life is dark with RGBW + Dimmer up, set `strobeOpen` to ~32 (its shutter is "low =
closed"). `isProvisional = false`.

### Robe Spiider — `SpiiderMode2Profile.swift` — **verified map, provisional arming**
Mode 2 "Basic" (27ch), offsets **verified against the official Robe chart v2.3**: pan/tilt 16-bit at
0–3, global RGBW at 7–10, zoom 24, **shutter 25** (`32 = open`, `64–95 = strobe`), dimmer 26. No
zoom-fine/dimmer-fine in this mode. Offset 5 (Power/Special) is deliberately **unmapped**. Stays
`isProvisional = true` because the *patched mode* is an on-the-day choice — the Spiiders stay dark
until you confirm Mode 2 and tap **ARM MOVERS**.

### Robert Juliat 860 Dalis MKII — `DalisStubProfile.swift` — **verified map, provisional arming**
Mode 3 "Full 1 group 8b" (13ch), **verified from the official RJ manual**: dimmer 0, R/G/B 1–3,
Cool White → 7 (the single `white` field), strobe duration 9, response-time 11 set to OFF so the
app's own fades aren't double-smoothed. Stays `isProvisional = true` pending the MKII personality
check. Dark until armed.

**Safety:** the renderer **skips provisional profiles entirely until armed** — Spiider/Dalis can
never emit garbage before their mode is confirmed.

---

<a name="confirm-checklist"></a>
## 8. ⚠️ On-the-day CONFIRM checklist

Each item is a one-place edit — no cue/show-logic changes.

1. **Spiider mode** — verified Mode 2 map is filled. Confirm the fixture is *patched* in Mode 2,
   confirm **RGBW mixing** is active (else R/G/B/W read as C/M/Y), then **ARM MOVERS**. If it's in
   Mode 1/3/4, re-pull that column into `SpiiderMode2Profile.swift`.
2. **Dalis** — confirm the MKII reports 13ch in **Mode 3** (`SETUP ▸ DMX ▸ PERSONALITY`), patch it,
   then **ARM MOVERS**.
3. **Fargo** — sweep Strobe / confirm Zoom direction / confirm offset-5 is Dimmer-fine and proof-of-
   life lights the unit. Edit the `Ch` table / range constants in `FargoProfile.swift` if needed.
4. **sACN universe numbers** — pick them in `lighting.json → universes`; tell the venue tech which
   ports carry universe 1 (Spiiders) and 2 (Fargo/Dalis).
5. **Network target** — `lighting.json → network.mode`: `multicast` (onto the venue's sACN LAN) or
   `unicast` (a node IP). On a Mac with Ethernet + Wi-Fi, prefer unicast or pin the interface so
   sACN leaves via the lighting LAN.

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
  "universes": { "spiider": 1, "fargoDalis": 2 },   // pick to match the venue's port assignment
  "fixtures": [ { "name": "Fargo1", "profile": "fargo_9ch", "universe": "fargoDalis", "address": 1 } ],
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

---

<a name="edm-timelines"></a>
## 11. EDM timelines (data, not code) — `Timelines/*.json`

Each EDM piece's lighting is a keyframe timeline mapped to **seconds** — editable/retimeable without
recompiling. A keyframe sets sparse semantic values (omitted fields default; `pan/tilt` default 0.5
= centre); `ease` is `hold`, `linear`, or `smooth`. Fixture tokens: `Fargos`, `Spiiders`, `Dalis`,
`All`, or a single name. The two Spiiders are authored mirrored (Spiider2 pan = 1 − Spiider1 pan).

```jsonc
{ "piece": "4", "template": "edm", "durationSeconds": 149,
  "tracks": [
    { "fixture": "Fargos", "keyframes": [
        { "t": 40, "ease": "hold", "state": { "red": 0.9, "blue": 0.3, "intensity": 1.0, "strobe": 0.65 } }
    ] } ] }
```

`SoloTemplate` / `TrioTemplate` build reusable cue lists from a `cycColor` + `intensity`;
`EDMTemplate` can synthesize a timeline from section markers (intro/build/drop/breakdown/outro) for
cloning the reference piece. Only `Timelines/torrent.json` (piece 4) is authored so far — the other
EDM pieces fall back to a clearly-labelled **NEUTRAL WASH (no timeline)** and log a note.

---

<a name="controls-reference"></a>
## 12. Controls reference

| Control | Where | Effect |
|---|---|---|
| **GO / STOP** | audio window (Space / Esc) | STOP **instantly hard-cuts** lighting (matches the audio panic); cleared on the next GO |
| **BLACKOUT** | Lighting window | instant kill latch |
| **HOLD** | Lighting window | freeze current look |
| **PROOF OF LIFE** | Lighting window | Fargo 1 white → fade |
| **PREV / NEXT CUE** | Lighting window | advance SOLO/TRIO cues |
| **ARM MOVERS** | Lighting window | enable Spiider/Dalis once their mode is confirmed |
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
| `Profiles/FargoProfile.swift` | Fargo 9ch (live) |
| `Profiles/SpiiderMode2Profile.swift` | Spiider Mode 2 27ch (verified, provisional arming) |
| `Profiles/DalisStubProfile.swift` | Dalis Mode 3 13ch (verified, provisional arming) |
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

Authoring the other four EDM timelines (`canon`, `moonlight`, `furelise`, `stilldre`) from per-track
audio analysis. They currently fall back to a neutral wash. Clone `Timelines/torrent.json`, set the
section times from each track, and preview with `--lighting-preview <piece> <seconds>`.
