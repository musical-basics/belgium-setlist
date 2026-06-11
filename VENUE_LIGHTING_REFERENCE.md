# Venue Lighting Reference — CC De Factorij (Theaterzaal Maupertuis), Zaventem

**Purpose: this file saves future sessions the research.** Everything below — the venue
inventory, the final patch, every DMX channel map, the gotchas, and where each config file
lives — was assembled from the venue's final plot, the technical rider, and the OFFICIAL
manufacturer DMX charts (sources linked per fixture). Trust it, don't re-derive it; if the
venue issues a new plot version, reconcile against `Lighting_Plot/` and update this file.

Show: Lionel Yu, Thu 11 June 2026. Lighting engine: `ShowRunnerApp/Sources/Lighting/`
(see `LIGHTING_README.md` for how the engine works; THIS file is about the venue + data).

---

## 1. Source-of-truth documents (in this repo)

| File | What it is |
|---|---|
| `Lighting_Plot/Lions patchv01.pdf` | **THE final patch sheet** (universe/address/fixture/mode) |
| `Lighting_Plot/Lions v01.pdf` | **THE final plot drawing** (6 pages: front bridge, top view, front view, side view, stage plot; author Bruno Peysmans, 11/6/2026) |
| `Technical Rider CC De Factorij EN (1).pdf` | venue rider (full house inventory, page 8) |

---

## 2. The venue's full lighting inventory (rider page 8 + plot legend)

What the house OWNS (we patch a subset — see §3):

| Fixture | Count | Type | Used in our show? |
|---|---|---|---|
| Robe Robin Spiider | 12 | LED wash mover, 7×40W RGBW + flower effect | **8** (Mode 3, 33ch) |
| Robe T1 Profile | ≥2 | LED profile mover, framing shutters, MSL 5-emitter engine | **2** (Mode 3, 53ch) |
| Robert Juliat Dalis 860 MKII | 14 | LED cyclorama batten, 8-colour engine | **7** (Mode 2, 22ch; plot says "default patch 11.1…") |
| Fargo StagePar 19 Pro Zoom MKII | 28 | RGBW LED par with zoom, 9ch mode | **No** — not in the final plot |
| Robe Robin Viva CMY | 8 | CMY spot mover (plot legend: Mode 1, 32ch) | No |
| Showtec LED Bar | 9 | LED batten | No |
| ADB Europe DS 205 | 15 | 2 kW profile (front catwalk) | **Yes** — part of FrontWash |
| ADB Europe C 203 | 8 | 2 kW PC (front catwalk) | **Yes** — part of FrontWash |
| MDG ATMe | 1 | oil-cracker hazer | venue-run (universe 1: 509 heater "always on", 510 pressure, 511 fog on/off, 512 fan) |
| House/venue lights | — | universe 1: 501 doors, 502 stairs, 503 parterre, 504 parterre ext., 505 balcony stairs, 506 balcony | venue-run |

**Venue DMX infrastructure:** sACN is the default protocol. Light network
**192.168.202.0/24 with a DHCP server**. 8 ceiling DMX/power looms + 10 floor DMX ports,
each assignable to any universe (rider) — coordinate which ports carry universes 2 and 3.

---

## 3. The FINAL patch (Lions patchv01.pdf) — what ShowRunner drives

### Universe 1 — front catwalk + house (conventionals)
| Addr | Unit | Ours? |
|---|---|---|
| 2–24 | 23 × 2 kW Profile/PC front catwalk (1ch dimmers; mix of DS 205 profiles and C 203 PCs) | **`FrontWash`** — one level across all 23 |
| 501–506 | house lights | no |
| 509–512 | MDG ATMe hazer | no (ask venue for steady low haze on EDM pieces) |

### Universe 2 — movers
| Addr | Fixture | Our name | Position (plot top view) |
|---|---|---|---|
| 1 | Spiider Mode 3 #1 | `Spiider1` | downstage batten, ≈ −2 m |
| 41 | Spiider Mode 3 #2 | `Spiider2` | downstage batten, ≈ +2 m |
| 81 | Spiider Mode 3 #3 | `Spiider3` | mid batten, ≈ −7 m |
| 121 | Spiider Mode 3 #4 | `Spiider4` | mid batten, ≈ +7 m |
| 161 | Spiider Mode 3 #5 | `Spiider5` | mid-up batten, ≈ −7 m |
| 201 | Spiider Mode 3 #6 | `Spiider6` | mid-up batten, ≈ +7 m |
| 241 | Spiider Mode 3 #7 | `Spiider7` | upstage batten, ≈ −3 m |
| 281 | Spiider Mode 3 #8 | `Spiider8` | upstage batten, ≈ +3 m |
| 321 | T1 Profile Mode 3 #1 | `T1L` | upstage-centre (≈ −1.5 m) — back-key on piano |
| 381 | T1 Profile Mode 3 #2 | `T1R` | upstage-centre (≈ +1 m) — back-key on piano |

Mirrored pairs: **1↔2, 3↔4, 5↔6, 7↔8** (right pan = 1 − left pan). Piano sits ≈ centre,
slightly left, angled (see stage plot page).

### Universe 3 — cyc row
| Addr | Fixture | Our name |
|---|---|---|
| 67 / 89 / 111 / 133 / 155 / 177 / 199 | Dalis 860 MKII Mode 2, plot labels "Dalis 4"…"Dalis 10" | `Dalis4`…`Dalis10` |

One even row upstage washing the cyc (white fond T40 / black fond T39 behind them).

---

## 4. DMX channel maps (from the OFFICIAL charts — do not re-research)

### 4.1 Robe Robin Spiider — Mode 3 "Advanced", 33 channels
Source: official Robe chart **"Robin SPIIDER - DMX protocol" v2.3**,
https://www.robe.cz/res/downloads/dmx_charts/Robin_SPIIDER_DMX_charts.pdf
Implemented in `Profiles/SpiiderMode3Profile.swift`. Colour system in Mode 3 = **global
(all-pixels) RGBW, 16-bit**; per-pixel control exists only in other modes.

| Ch | Function | Notes / safe value |
|---|---|---|
| 1/2 | Pan coarse/fine | 540° |
| 3/4 | Tilt coarse/fine | 220° |
| 5 | Pan/Tilt speed | 0 = standard |
| 6 | **Power/Special functions** | **KEEP 0.** Values ≥10 held 3 s (with shutter closed) latch resets / mix-mode / parking. 185/186 select PWM 300/600 Hz |
| 7 | Virtual colour wheel | **0** = open, RGBW channels in control |
| 8/9 | Red coarse/fine | doubles as Cyan in CMY mix mode |
| 10/11 | Green coarse/fine | |
| 12/13 | Blue coarse/fine | |
| 14/15 | White coarse/fine | no function in CMY mode |
| 16 | CTC | 0 = off |
| 17 | Colour mix control | 0–9 = global priority (we use 0); factory default 45 = addition |
| 18/19/20 | Pixel effects / speed / fade | 0 = off |
| 21 | **Flower effect** | **0 = OFF** (1–255 spins it) |
| 22–25 | Flower RGBW | 0 |
| 26 | Flower colour macros | 0 |
| 27 | Flower shutter | park 32 (inert while ch21 = 0) |
| 28 | Flower dimmer | 0 |
| 29/30 | **Zoom** coarse/fine | **INVERTED: DMX 0 = WIDEST**, 255 = narrowest (profile writes 1 − zoom) |
| 31 | **Shutter/strobe** | **0–31 = CLOSED · 32–63 = open (32 default) · 64–95 = strobe slow→fast** · 192–223 random strobe |
| 32/33 | Dimmer coarse/fine | |

### 4.2 Robe T1 Profile — Mode 3 "Five colours", 53 channels
Source: official Robe chart **"Robin T1 Profile DMX charts" v2.1**,
https://www.robe.cz/res/downloads/dmx_charts/Robin_T1_Profile_DMX_charts.pdf
Implemented in `Profiles/T1Mode3Profile.swift`. Mode 3 exposes the **five raw LED emitters
(R/G/B/Amber/Lime), each 16-bit** — no CMY in this mode. Open white = all five at full.

| Ch | Function | Notes / safe value |
|---|---|---|
| 1/2, 3/4 | Pan (540°), Tilt (265°) 16-bit | |
| 5 | P/T speed | 0 |
| 6 | **Power/Special** | **KEEP 0** (10+ latch menu overrides / resets) |
| 7 / 8 | LED freq select / fine | park **10 / 128** (600 Hz, no offset) |
| 9 | Colour functions | 0 |
| 10 | CRI select | 0 = standard 80 |
| 11 | Virtual colour wheel | **0** = open |
| 12/13 | Red 16-bit | |
| 14/15 | Green 16-bit | |
| 16/17 | Blue 16-bit | |
| 18/19 | Amber 16-bit | |
| 20/21 | Lime 16-bit | |
| 22 | **CTO** | **park 110 = neutral 5600 K** (0 = 8000 K — a blue beam if you park it at 0!) |
| 23 | Green correction | **park 128** = uncorrected |
| 24 | Colour mix control | 0 = default priority |
| 25 | Rot. gobo selection speed | 0 |
| 26 | Effect-time engine | 0 = off |
| 27 / 28 / 29 | Effect wheel pos / rot / animations | 0 / **128** / 0 |
| 30 / 31 / 32 | Rot. gobo wheel / index / fine | 0 (open) / **128** / 0 |
| 33 / 34 | Prism / prism rotation | 0 (out) / **128** |
| 35 | Frost | 0 = open |
| 36/37 | Iris / fine | 0 = open |
| 38/39 | **Zoom** 16-bit | **INVERTED: DMX 0 = widest** |
| 40/41 | Focus 16-bit | park **128** |
| 42 | Framing module rotation | park **128** = centred |
| 43–50 | Framing blades 1–4: movement / swivel ×4 | movement **0** = blade out; swivel **128** = 0° |
| 51 | **Shutter/strobe** | **0–31 closed · 32 = open · 64–95 strobe** |
| 52/53 | Dimmer 16-bit | |

### 4.3 Robert Juliat Dalis 860 (MKII) — Mode 2 "Full 1 group mode 16b", 22 channels
Source: official RJ manual **DN41077600-B (V2.XX)**,
https://www.robertjuliat.com/PDF/Documents/DN41077600b_m_DALIS_860_v2.pdf (DMX chart §5.2.4)
Implemented in `Profiles/DalisMode2Profile.swift`. The 8-LED colour engine, **in channel
order**: Red, Green, Blue, Royal blue, Cyan, Amber, Cool white 6500 K, Warm white 2200 K.

| Ch | Function | Notes |
|---|---|---|
| 1/2 | Dimmer 16-bit | |
| 3/4 | Red | all colours 16-bit |
| 5/6 | Green | |
| 7/8 | Blue | ~470 nm; for DEEP blue consider blending Royal blue |
| 9/10 | Royal blue | unused by our profile (0) |
| 11/12 | Cyan | unused (0) |
| 13/14 | Amber | unused (0) |
| 15/16 | Cool white 6500 K | ← our `white` field |
| 17/18 | Warm white 2200 K | unused (0) |
| 19 | Strobe duration | **0 = strobe OFF (open)**; 1–255 = flash 1–85 ms |
| 20 | Strobe speed | 5.8–11.5 Hz; only acts while ch19 ≥ 1 |
| 21 | Response time | 0–250 = 0.1–4 s smoothing; **251–255 = OFF** (we park 255 so the app's fades aren't double-smoothed) |
| 22 | Control mode | 0 = default (RDM active) |

Other Dalis modes for reference: Mode 1 = 70ch (4 groups 16b), Mode 3 = 13ch (1 group 8b),
Mode 4 = 8ch (presets 16b), Mode 5 = 7ch (presets 8b), Mode 6 = 72ch.

### 4.4 Front catwalk 2 kW conventionals (ADB Europe DS 205 / C 203)
Plain 1-channel dimmers, universe 1 addr 2–24. Driven by `Profiles/FrontWashProfile.swift`
as ONE submaster level. Their focus is the venue's — ask for an even piano-centred wash.

### 4.5 Unused but available (if a future design wants them)
- **Robe Robin Viva CMY** — plot legend says Mode 1, 32 channels. Chart:
  https://www.robe.cz/res/downloads/dmx_charts/Robin_Viva_CMY_DMX_charts.pdf (fetch before use).
- **Fargo StagePar 19 Pro Zoom MKII** — 9ch order R,G,B,W,Dim,DimFine,Strobe,Color,Zoom
  (from a verified Dutch theatre patch; no official value chart published). Our old verified
  profile is preserved at `backup/lighting-rig-v1/FargoProfile.swift`.
- **Showtec LED Bar** — no mode info gathered.

### Cross-fixture gotchas (the things that bite)
1. **Robe shutters: 0 = CLOSED.** "No strobe" must write 32. Both Spiider ch31 and T1 ch51.
2. **Robe zoom is inverted** on both Spiider and T1: DMX 0 = widest beam.
3. **T1 CTO parks at 110**, not 0 (0 = 8000 K cold blue).
4. **Never write Robe Power/Special channels** (Spiider ch6, T1 ch6) — resets/parking live there.
5. **Dalis response time** must be 251–255 to disable fixture-side smoothing.
6. **Spiider flower effect ch21 must stay 0** or the beam turns into a spinning flower.
7. **T1 tilt is INVERTED** (the two upstage-centre T1s are yoked opposite to the Spiider rig the timelines author against). `T1Mode3Profile` writes `1 − tilt` so the beam lands on the piano, not back up on the cyc/screen.

---

## 5. Our config & data files (the complete map)

| File | Role |
|---|---|
| `lighting.json` | **The patch + per-piece lighting config.** Fixtures (names → profiles → universe roles → addresses), sACN network mode, piece templates, and the **`stage` piano anchor** (see §5.1). Read at launch; never affects audio. Universe roles: `front`=1, `movers`=2, `dalis`=3 |
| `Timelines/torrent.json` | Piece 6 (Torrent Etude) EDM timeline — **the reference**. 10 tracks: `Front`, `Dalis`, `T1s`, `Spiider1`, `Spiider2`, `Spiider3+Spiider5`, `Spiider4+Spiider6`, `Spiider7`, `Spiider8`. Section times measured from the backing track (see §6) |
| `Timelines/furelise.json` (7) / `canon.json` (8) / `moonlight.json` (9) / `fourseasons.json` (13) / `stilldre.json` (E3) | The other authored EDM timelines, same 10-track structure, section times measured per §6.x. **Four Seasons** cycles the full season-colour gamut: dawn → SPRING green/blossom (21 s) → SUMMER amber/blazing hot (106.5) → AUTUMN russet (137) → WINTER ice blue/white (196.5, THE 211.2 hit). **Still D.R.E.** is Lakers **purple & gold** (a combo no other piece uses), slow heavy rocking, zero strobe |
| `Timelines/fantaisie.json` / `prelude.json` / `rollingthunder.json` / `fightforfreedom.json` / `colorsofthesoul.json` / `dreamsofaviolin.json` (10) / `gallop.json` (11) / `beethovenvirus.json` (12) / `sunflowers.json` (E1) / `bumblebee.json` (E2) | Self-driven looping timelines for live (non-audio) pieces — `template: "auto"` runs them on the renderer's own wall clock, seamless loop (t=0 state == t=end state). Briefs: Dreams of a Violin = dreamy magenta+lavender/soft-blue/teal slow rotation; Gallop = earthy blue/green canter (2–3 pan cycles/loop); Beethoven Virus = fiery red/purple/green colliding on phase-offset stacks; Sunflowers = peaceful breathing gold; Bumblebee = will-o'-the-wisp ghost-green/teal narrow darting beams in the dark. None strobe |
| `showrunner.json` | The AUDIO show config (running order, audio routing, speech notes). Lighting only reads piece `order` strings from it indirectly |
| `ShowRunnerApp/Sources/Lighting/Profiles/*.swift` | The four fixture profiles (channel maps live HERE, one file per mode) |
| `ShowRunnerApp/Sources/Lighting/LightingConfig.swift` | `lighting.json` loader; its `defaults()` mirrors the final plot if the JSON is missing |
| `backup/lighting-rig-v1/` | The pre-plot provisional rig (Fargo/Spiider Mode 2/Dalis Mode 3 profiles + old lighting.json/torrent.json) |
| `LIGHTING_README.md` | How the lighting ENGINE works (architecture, windows, controls, commands) |
| `Lighting module context.md` | The original build brief |

Timeline JSON format details (group tokens, `+`-joined tracks, ease types, the
"omitted fields fall back to defaults — restate colour+pan+tilt+zoom on mover keyframes"
rule) are in `LIGHTING_README.md` §11.

**Arming model:** Dalis + FrontWash emit immediately. Spiiders + T1s are `isProvisional`
and stay DARK until the operator confirms the patched modes match the plot and taps
**ARM MOVERS** in the Lighting window. PROOF OF LIFE targets Dalis 4.

### 5.1 The `stage` piano anchor — point the whole mover rig at the piano in ONE edit

This is a piano show, so the mover rig (8 Spiiders + 2 T1s) is **parametrised on where the piano
sits** rather than re-aimed by hand in every timeline. One block in `lighting.json`:

```jsonc
"stage": { "pianoPan": 0.46, "pianoTilt": 0.40, "stretch": 1.0 }
```

- **`pianoPan` / `pianoTilt`** (0…1, 0.5 = stage centre) — the **root**: where the piano is. Plot
  puts it centre, slightly left → `pianoPan` just under 0.5. **Piano moves → change these two, done.**
- **`stretch`** — single gain on each mover's deviation from the root:
  `finalAim = root + (authoredAim − root) × stretch`, clamped 0…1.
  `1.0` = **identity / authored looks unchanged** (the default) · `< 1` pulls the rig **in toward the
  piano** (`0` = every beam on the piano) · `> 1` fans wider than authored.
- **Scope:** pan/tilt only (all movers); colour, intensity, zoom and FrontWash/Dalis are untouched.

**Last-minute adjustment = a config edit, NOT a code change.** Edit the three numbers, relaunch (or
preview headless: `--lighting-preview out.png 6 50.9`, Torrent drop 1 — a wide-fan moment so the
change is obvious). The live rig and the preview focal point share the transform and both follow.

**Don't rewrite the logic** — it already exists and is verified: transform in
`Rig.applyStageAnchor(_:)` (called from `Renderer.tick()` after `computeFrame`, and from
`LightingPreview`), config in `LightingConfig.StageAnchor`. Full how-to: `LIGHTING_README.md` §10
"The piano anchor". For a show-day tweak, **touch only `lighting.json` → `stage`.**

---

## 6. Torrent audio analysis (measured section times, piece 6)

From band-split FFT energy analysis (bass 20–150 Hz / mid / high 4–16 kHz, 0.25 s frames)
of `ShowAudio/Torrent Etude Nightmare/Backing.wav` (149.27 s, 48 kHz stereo):

| t (s) | Event |
|---|---|
| 2.9 | music in (bass enters) |
| 11.3 | groove kicks (first heavy bass) |
| 24.0 | section lift |
| 32 → 50.7 | build (highs ramp continuously) |
| **50.9** | **DROP 1** (full spectrum opens) |
| 76.5 | hard cut to silence |
| 77.5–83.6 | piano interlude (quiet) |
| 83.8–85.3 | near-silence dip |
| 85.5 → 98.1 | rebuild 1 (bass ramp, peak ~96–98) |
| 98.4 | hard cut |
| 99.8 → 109.3 | rebuild 2 |
| **109.5** | **DROP 2** (sustained to 134.4) |
| 134.6 | hard cut |
| 135.2 → 137.4 | final swell |
| 137.5–141.5 | climax (peak highs at ~141) |
| 142–146 | wind-down |
| 148.5 | silence |

Method (reusable for the other 4 EDM pieces): read the WAV with numpy, 0.25 s hop, FFT per
window, normalised band envelopes; drops = the instant the high band opens after a build;
cuts = full-band collapse to ≈0 within one frame.

### 6.1 Für Elise Nightmare (piece 7) — measured (192.00 s)
Romantic→nightmare arc. Music in ≈18 s · romantic swell peak ≈35 · cut 37 · groove enters
57.5 · first full section ≈60 · pull-back 65–75 · rebuild 90–105 · cut 107 · purple
transition 110–135 · nightmare riser 135–140 · **NIGHTMARE DROP 140.75** · sustained climax
140–160 (dense bass kicks) · collapse 163 · soft romantic reprise 165–188 · out by 190.

### 6.2 Canon in Dream (piece 8) — measured (291.38 s)
EDM throughout (no reg/nightmare split). Regal groove in from 0 · accent ≈40 · **DROP 1 at
67** · heroic section 67–92 · **long quiet "dream" interlude ≈95–170** (backing drops near the
noise floor — soft ambient, NOT black) · rebuild 170–175 · big heroic build 175–225 ·
**DROP 2 at 227.5** · climactic drop cluster 235/245/254/262/270/275 · cut 280 · tail 285 · out 291.

### 6.3 Moonlight Sonata Nightmare (piece 9) — measured (180.83 s)
Reg moonlight→nightmare. Music in 3.25 s · moonlight develops 20–60 · reg climax ≈60–70 ·
**break (near-silence) ≈75** · purple tension rebuild 80–100 · **NIGHTMARE DROP 101.25**
(electric) · electric peak ≈115 (high band 0.89) · bass hits 125/135/140 · re-drops **145.25 ·
155.25 · 164.25** · wind-down 168–176 · out by 180.

### 6.4 Four Seasons Nightmare (piece 13) — measured (278.24 s)
Four blocks separated by quiet interludes → mapped to the season cycle. Dawn intro 4.5 ·
SPRING 21–105 (first sparkle 21, full 24–47, airy bass-out string breaks 48/57.5/67, peaks
80/91.5/100.5) · break 103 → SUMMER 106.5–136 (dark sultry start, build 115, storm peaks
125–131) · AUTUMN interlude 137 (dance 153–174, peak 163, hush 175.5, rebuild 189) · drop
196.5 → WINTER (rebuild 201, **THE HIT 211.2 — biggest of the piece, bass 0.94**, storm
peaks 215/221/223.5, dip 246.5, final climax 249–273 with highs 0.8–0.9, collapse 273.5,
out 277).

### 6.5 Still D.R.E. (piece E3) — measured (146.43 s)
Iconic piano riff alone 4.75–37 (phrase dip 26.5–29.8) · single hit 37.2 · dead silence
39.5–41.6 · **BEAT DROPS 41.75** (bass-only groove) · hats 48 · chorus 57.5 with big bass
accents every ~5 s (61.5/66/71/76) · verse 78.5 · **HARD CUT to silence 97.4** · piano
re-enter 105 · **chorus 2 at 107.5** (peaks 117–123) · final hit 132.2 · echo pulses
137.2/142 · out ~146.

---

## 7. What a future session still has to do

1. All show timelines are authored (EDM: 6/7/8/9/13/E3; auto-loops for the live piano
   pieces). For any new piece: clone torrent.json's 10-track structure and measure the
   audio with the §6 method.
2. On the day: the 7-step checklist in `LIGHTING_README.md` §8 (proof of life → confirm
   modes → ARM MOVERS → colours → front wash → network → haze).
3. If the venue revises the plot ("Lions v02"?), diff against §3 and update
   `lighting.json` + this file.
