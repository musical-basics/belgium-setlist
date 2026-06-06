# Build Brief: "ShowRunner" — a minimal live concert playback app

**For:** Claude Code (build this from scratch). This document is self-contained;
you do not need any prior conversation. Read it fully, then build.

**Client:** Lionel Yu, classical pianist + EDM performer. Mac. Live concert in
Zaventem, Belgium on **Thu 11 June 2026**. This app replaces QLab for his show.

**One-line goal:** A dead-simple, rock-solid macOS app that, on a single
keypress per piece, (1) plays a backing track to audio outputs 1-2 and a click
track to outputs 3-4 *simultaneously and sample-locked*, and (2) shows a
full-screen title-card image on the projector display with a 1-second fade in/out.
No timeline, no GUI fiddliness, no licensing. It must not crash mid-show.

---

## CRITICAL HARDWARE/PLATFORM CONSTRAINTS (read first — these pick your stack)

1. **Multichannel output is mandatory and is the hard requirement.** Audio device
   is an **Audient iD44** (USB audio interface, multiple discrete outputs).
   - Backing track → **device outputs 1 & 2** (front-of-house PA).
   - Click track → **device outputs 3 & 4** (performer's in-ear monitor).
   - These are SEPARATE physical outputs on the same device. The app must address
     individual output channels. **A browser/Web Audio app CANNOT do this**
     (Web Audio is limited to the default stereo output). Do NOT build a web app.
2. **Target stack: native macOS.** Strong recommendation: **Swift + AVFoundation
   (AVAudioEngine)**, which gives precise CoreAudio channel mapping, sample-locked
   multi-file playback, and native full-screen on a chosen display. Acceptable
   alternative if you must: Python 3 with `sounddevice`/`PortAudio` for audio +
   a native window for video — but Swift is preferred for reliability and a clean
   single-app bundle. Pick ONE and commit; do not split audio and video across
   two processes if avoidable.
3. **Backing + click must start at the exact same sample.** Lionel plays live
   piano along to the click; any drift between backing and click is fatal. Use a
   single engine/clock that starts both buffers on the same render tick (e.g.
   AVAudioPlayerNode scheduled to a shared start time, or a single multi-channel
   buffer — see "Audio design" below).
4. **Two displays.** The Mac's main display = operator screen (shows the control
   UI). A second display = the projector/TV for the audience (shows title cards).
   The app must let the operator pick which display is the audience output, and
   must NOT show the control UI on the audience display. (At the venue the second
   display may be a different resolution, e.g. 1280×800 or 1920×1080 — letterbox
   the image to fit, never crash if resolution differs.)

---

## THE SHOW DATA (drives everything)

The concert has 15 pieces in order. Files live under:
`/Users/lionelyu/Music/Belgium Concert Program/`
…in per-piece folders. Each piece folder is named `NN - Piece Name`.

**Make the app config-driven** by a single JSON file (`showrunner.json`) the app
reads at launch, so Lionel can edit the running order without recompiling. Build a
small generator or just hand-write this JSON from the table below. Schema:

```json
{
  "audienceDisplayIndex": 1,
  "audioDeviceName": "Audient iD44",
  "fadeSeconds": 1.0,
  "pieces": [
    {
      "order": "1",
      "title": "Prelude in G minor",
      "subtitle": "Sergei Rachmaninoff, Op. 23 No. 5",
      "folder": "01 - Rachmaninoff Prelude G minor",
      "titleCard": "TitleCard.png",
      "hasAudio": false,
      "backing": null,
      "click": null
    }
    // ... etc
  ]
}
```

**Full piece list** (order, title, subtitle, folder, hasAudio, backing file, click file):

| # | Title | Subtitle | Folder | Audio? | Backing | Click |
|---|---|---|---|---|---|---|
| 1 | Prelude in G minor | Sergei Rachmaninoff, Op. 23 No. 5 | 01 - Rachmaninoff Prelude G minor | no | — | — |
| 2 | Colors of the Soul | Lionel Yu | 02 - Colors of the Soul | no | — | — |
| 3 | Gallop | Lionel Yu · piano trio | 03 - Gallop (Trio) | no | — | — |
| 4 | Torrent Etude Nightmare | Chopin · arr. Lionel Yu | 04 - Torrent Etude (EDM) | yes | Backing.wav | Click.wav |
| 5 | Beethoven Virus | arr. Lionel Yu · piano trio | 05 - Beethoven Virus (Trio) | no | — | — |
| 6 | Canon in Dream | Remix of Pachelbel's Canon in D | 06 - Canon in Dream (EDM) | yes | Backing.wav | Click.wav |
| 7 | Fight for Freedom | Lionel Yu | 07 - Fight for Freedom (maybe) | no | — | — |
| 8 | Winter Wind Etude | Frédéric Chopin, Op. 25 No. 11 | 08 - Winter Wind | no | — | — |
| 9 | Moonlight Sonata Nightmare | Remix of Beethoven's Moonlight Sonata | 09 - Moonlight Sonata (EDM) | yes | Backing.wav | Click.wav |
| 10 | Sunflowers | Lionel Yu | 10 - Sunflowers | no | — | — |
| 11 | Dreams of a Violin | Lionel Yu · violin & piano | 11 - Dreams of a Violin (Duet) | no | — | — |
| 12 | Für Elise Nightmare | Remix of Beethoven's Für Elise | 12 - Fur Elise Dubstep (EDM) | yes | Backing.wav | Click.wav |
| E1 | Fantaisie-Impromptu | Frédéric Chopin, Op. 66 | E1 - Fantasie Impromptu | no | — | — |
| E2 | Flight of the Bumblebee | Rimsky-Korsakov | E2 - Flight of the Bumblebee | no | — | — |
| E3 | Still D.R.E. | arr. Lionel Yu | E3 - Still Dre (EDM) | yes | Backing.wav | Click.wav |

Notes:
- Every folder already contains `TitleCard.png` (1920×1080, dark background, gold
  rule, title + subtitle). The app should display these as-is. (If you'd rather
  render titles from the title/subtitle text natively, that's acceptable too —
  but the PNGs exist and look good, so simplest is to display them.)
- Only the 5 EDM pieces have audio (`hasAudio: true`). The other 10 are solo/acoustic
  — for those, GO just shows the title card; no audio plays.
- The audio WAVs: 44.1 or 48 kHz, 16-bit, stereo. Backing and matching Click in a
  given folder are the SAME length (already verified). Handle sample-rate per file.

---

## AUDIO DESIGN (the core; get this exactly right)

- Device: open the output device whose name contains "Audient iD44" (match
  loosely; fall back to a device picker if not found — never hard-crash).
- The device exposes ≥4 output channels. Build an output channel map so:
  - backing stereo file: its L → device out 1, its R → device out 2
  - click stereo file: its L → device out 3, its R → device out 4
- **Simplest robust approach in AVAudioEngine:** create one AVAudioEngine with the
  output node configured for the device's full channel count (≥4). Use two
  AVAudioPlayerNodes (backing, click). Connect backing to a channel-mapped node
  routing to out 1-2, click routing to out 3-4. Schedule BOTH with
  `scheduleBuffer`/`scheduleFile` at a shared `AVAudioTime` slightly in the future
  so they begin on the same render cycle (sample-locked). Verify drift = 0.
  - If channel mapping via AVAudioEngine connection points is awkward, an
    equally valid approach: pre-mix backing+click into ONE interleaved 4-channel
    buffer at load time (ch0=backingL, ch1=backingR, ch2=clickL, ch3=clickR) and
    play that single buffer to a 4-channel output. This GUARANTEES sample-lock and
    is the most bulletproof option. **Prefer this if in doubt.**
- Master "panic/stop" must instantly stop all audio and reset.
- Loudness: play files at unity (0 dB), no added gain. Provide a master volume
  only if trivial; not required.

## VIDEO DESIGN

- On launch, enumerate displays. Audience display = config `audienceDisplayIndex`
  (default 1 = secondary). Operator can change via a dropdown in the control UI.
- Open a borderless full-screen window on the audience display, black background.
- On GO for a piece: load that piece's `TitleCard.png`, display it centered/
  letterboxed (preserve aspect, fill black around it), **fade opacity 0→1 over
  `fadeSeconds`**.
- On NEXT/advance or explicit "clear": **fade 1→0** then show black.
- Never show the macOS desktop, menu bar, or the control UI on the audience screen.
- If only ONE display is present (testing at home), allow a "windowed preview"
  mode so Lionel can see the card in a window on the main screen.

## CONTROL UI (operator screen — keep it brutally simple)

- A vertical list of the 15 pieces in order, big readable rows: number + title.
  Current piece highlighted.
- **Spacebar = GO** = fire the currently-selected piece (show title card with fade;
  if hasAudio, start backing+click sample-locked).
- **Down/Up arrows** = move selection to next/previous piece (do NOT fire).
- **Enter** could also = GO on selected. Make GO dead obvious.
- A big **STOP / PANIC** button and a hotkey (e.g. Esc) that instantly stops audio
  and fades the card to black.
- Show, per piece: a tiny indicator of whether audio is present and whether files
  were found (green = ready, red = missing file). Show elapsed time of the
  currently-playing audio so Lionel knows where he is.
- That's it. No editing, no drag-drop, no timelines. The running order comes from
  the JSON.

## RELIABILITY REQUIREMENTS (this is for a paid live show)

- Must not crash if a file is missing — show it red, skip gracefully on GO.
- Must not crash if the audio device is absent at launch — show a device picker.
- Must not crash if there's only one display — fall back to windowed preview.
- Pre-load all audio buffers and images at launch (or on selection) so GO is
  instant with no disk-stall hitch.
- Log to a file so failures can be diagnosed.
- Provide a 60-second "self-test" command that, for each EDM piece, confirms the
  backing and click files load, are equal length, and route to 1-2 / 3-4.

## DELIVERABLES

1. A buildable macOS app (Xcode project if Swift) with a single double-clickable
   `.app`, OR a `swift run` / `python3 showrunner.py` entry point — whichever is
   most reliable. Document the exact run command.
2. `showrunner.json` pre-filled with the 15 pieces from the table above.
3. A short README: how to launch, how to pick the audience display + audio device,
   the keybindings, and how to edit the running order.
4. The self-test command/output.

## ACCEPTANCE TEST (Lionel will run this)

1. Launch → 15 pieces listed, EDM pieces show "audio ready" (green).
2. Select Canon in Dream, press GO → title card fades up on the projector display;
   backing audibly comes from PA (outs 1-2), click ONLY in the in-ears (outs 3-4),
   perfectly in sync, no flam.
3. Press STOP → audio stops instantly, card fades to black.
4. Select a non-EDM piece (e.g. Winter Wind), GO → title card fades up, no audio.
5. Unplug a file / device → app shows red, doesn't crash.

---

### Context the builder may want (optional background)
- These assets were originally built for QLab 5; QLab's GUI/AppleScript/licensing
  friction is why we're replacing it. The audio routing requirement (separate
  physical outs for click vs backing) is exactly what makes this need to be native.
- Title-card PNGs already generated and located in each piece folder.
- The "maybe"/encore pieces (7, E1) are tentative — keep them in the list; Lionel
  decides live whether to play them.

Build it to be boring and unbreakable. Ship the simplest thing that passes the
acceptance test.
