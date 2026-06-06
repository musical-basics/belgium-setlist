# ShowRunner

A dead-simple, rock-solid macOS playback app for Lionel's live concert
(Zaventem, Belgium — Thu 11 June 2026). Replaces QLab.

On one keypress per piece it:

1. Plays the **backing track to outputs 1·2** (front-of-house PA) and the
   **click track to outputs 3·4** (in-ear monitor), **sample-locked** (zero drift), and
2. Shows the piece's **full-screen title card** on the projector display with a 1-second
   fade in/out.

No timeline, no editing, no licensing. Built to be boring and unbreakable.

---

## Quick start

```bash
cd "/Users/lionelyu/Music/Belgium Concert Program/ShowRunnerApp"
./build.sh           # builds ShowRunner.app next to showrunner.json
open "../ShowRunner.app"
```

…or for development without the bundle:

```bash
swift run -c release ShowRunner
```

Self-test (no windows — verify everything is in place before the show):

```bash
swift run -c release ShowRunner --selftest
# or, after build.sh:
"../ShowRunner.app/Contents/MacOS/ShowRunner" --selftest
```

The app reads **`showrunner.json`** from the concert folder
(`/Users/lionelyu/Music/Belgium Concert Program/showrunner.json`).

---

## Keybindings (operator screen)

| Key | Action |
|-----|--------|
| **Space** / **Enter** | **GO** — fire the selected piece (title card fades up; if EDM, backing+click start sample-locked) |
| **↓** | Move selection to next piece (does **not** fire) |
| **↑** | Move selection to previous piece (does **not** fire) |
| **Esc** | **STOP / PANIC** — instantly stop audio and fade the card to black |

The big green **GO** and red **STOP / PANIC** buttons do the same thing with the mouse.
Clicking a row selects it.

---

## Picking the audio device and audience display

Both are dropdowns at the top of the operator window:

- **Audio device** — defaults to the one named in `showrunner.json` (`Audient iD44`).
  If it isn't found, the app falls back to the system default output and **does not crash**;
  just pick the right device from the menu. A device must expose **≥ 4 output channels**
  to route the click to outs 3·4 — if it has only 2, the backing still plays to 1·2 and the
  status line warns that the click is not routed.
- **Audience display** — lists every connected screen. Choosing a screen **other than the
  operator's** opens a borderless full-screen black window there and shows title cards
  letterboxed (aspect preserved, black bars, any resolution). Choosing the operator's own
  screen (or having only one screen) shows a **windowed preview** so you can test at home.

Routing is fixed and shown in the status line:
`backing L/R → out 1/2`, `click L/R → out 3/4`.

---

## Editing the running order

Edit **`showrunner.json`** (next to the app). No recompile needed — it is read at launch.

```jsonc
{
  "audienceDisplayIndex": 1,        // default audience screen (0 = main, 1 = secondary…)
  "audioDeviceName": "Audient iD44",// loose name match
  "fadeSeconds": 1.0,               // title-card fade in/out duration
  "engineSampleRate": 48000,        // device + all audio locked to this rate for the whole show
  "pieces": [
    {
      "order": "1",
      "title": "Prelude in G minor",
      "subtitle": "Sergei Rachmaninoff, Op. 23 No. 5",
      "folder": "01 - Rachmaninoff Prelude G minor", // relative to the concert folder
      "titleCard": "TitleCard.png",
      "hasAudio": false,            // true only for the 5 EDM pieces
      "backing": null,              // e.g. "Backing.wav" when hasAudio
      "click": null                 // e.g. "Click.wav"   when hasAudio
    }
    // …15 pieces total
  ]
}
```

To reorder, just move objects in the `pieces` array. To add audio to a piece, set
`hasAudio: true` and point `backing`/`click` at WAV files inside that piece's `folder`.

---

## How it works (the important bits)

- **Sample-lock.** Each EDM piece's backing and click are read, resampled to a single fixed
  rate (48 kHz) with identical settings, and laid into **one 4-channel buffer**
  (ch0/1 = backing L/R, ch2/3 = click L/R). A single CoreAudio render callback plays from
  that one buffer with **one shared play head**, so backing and click are sample-locked
  by construction — there is no second clock to drift against.
- **Channel routing.** A HAL output unit is bound directly to the device. Its input is the
  full device channel width, so channel _i_ maps to physical output _i_ with no ambiguous
  channel-map — the callback fills outs 1–4 and zeroes the rest.
- **No mid-show relock.** The device is locked to 48 kHz once at launch; every file is
  pre-resampled at load, so changing pieces never re-clocks the interface.
- **Lock-free GO.** The audio unit is stopped while the active buffer is swapped, then
  restarted — no real-time locks or allocations, and no torn reads.
- **Pre-loaded.** All title-card images and all audio buffers are loaded at launch, so GO
  is instant with no disk stall.

## Reliability / what won't crash it

- **Missing file** (title card / WAV) → that piece shows **red** ("MISSING"); GO still works
  (shows whatever exists; no audio if the WAV is gone).
- **Audio device absent / wrong** → falls back to the system default output; pick the right one
  from the menu. If the current device has **fewer than 4 outputs** (so the click can't reach
  outs 3·4), GO on an EDM piece is **deliberately blocked** with `⛔ … Select the Audient iD44`
  rather than blasting the backing out the wrong output. Title-card-only pieces always fire.
- **Device unplugged mid-show** → playback stops instantly and the operator sees
  `⛔ AUDIO DEVICE DISCONNECTED — reconnect & re-select it`. Reconnect and re-pick it; no crash.
- **Only one display** → windowed preview instead of full-screen.
- **Different projector resolution** (1280×800, 1920×1080, …) → the card is letterboxed, never
  stretched, never crashes.

## Logs & self-test

- Every launch/GO/STOP/error is logged to **`~/Library/Logs/ShowRunner/showrunner.log`**
  (also echoed to stderr).
- `--selftest` confirms: config loads, the audio device is present with ≥ 4 outputs, every
  title card exists, and every EDM piece's backing + click load, are (near-)equal length, and
  route to 1·2 / 3·4. Exit code 0 = pass.

> Note on _Canon in Dream_: its backing and click differ by ~74 ms in length (the click ends
> slightly earlier). The shorter is padded with silence; the **start** stays perfectly locked.
> The self-test flags this as a benign warning.

## Requirements

- macOS 13+ (built/tested on 14.3.1, Apple Silicon).
- Builds with **Command Line Tools only** (no full Xcode needed): `swift build`.
