# ShowRunner — your own QLab replacement (Python)

A tiny, field-editable playback app for the Belgium concert. One keypress per
piece: plays backing→PA (outs 1-2) + click→in-ears (outs 3-4) sample-locked, and
shows the title card full-screen on the projector with a fade.

**You can edit `showrunner.py` and `showrunner.json` in any text editor at the
venue and just re-run.** No Xcode, no compiling, no licensing.

---

## ONE-TIME SETUP (do this at home, not at the venue)

```bash
# 1. PortAudio (the audio engine sounddevice needs)
brew install portaudio

# 2. Python libraries
pip3 install sounddevice soundfile numpy pillow pyobjc
#   - sounddevice/soundfile/numpy = audio
#   - pillow = title-card images + fades
#   - pyobjc = lets it find your second display precisely (optional but recommended)
```

If `pip3` complains about the system Python, use:
`pip3 install --user sounddevice soundfile numpy pillow pyobjc`

## RUN

```bash
cd "/Users/lionelyu/Music/Belgium Concert Program/ShowRunner"

python3 showrunner.py              # the show: control window + fullscreen titles
python3 showrunner.py --windowed   # title card in a window (testing on one screen)
python3 showrunner.py --selftest   # checks every file + the audio device, no GUI
python3 showrunner.py --list-devices    # show audio devices (find the Audient)
python3 showrunner.py --list-displays   # show monitors + their indexes
```

**Always run `--selftest` first at the venue.** It prints, for every EDM piece,
that the files load, their length, and that they route to ch 1-2 / 3-4. Green =
good to go.

## KEYS (in the control window)

| Key | Action |
|-----|--------|
| **Space** or **Return** | GO — fire the selected piece (card fades in; audio if any) |
| **Down / Up** | move selection (does NOT fire) |
| **C** | clear the title card (fade to black), audio keeps playing |
| **Esc** or **S** | PANIC — stop audio + fade card to black |
| **Q** | quit |

There are also big GO and STOP/PANIC buttons.

## HOW IT WORKS (so you can fix it)

- **Audio:** for each EDM piece it builds ONE interleaved 4-channel buffer —
  channels 0,1 = backing (→ device outs 1,2), channels 2,3 = click (→ outs 3,4).
  Playing one buffer off one clock means backing and click can NEVER drift.
  (Canon's backing/click differ by 0.07s; the app pads the short one so they
  start together — handled automatically.)
- **Video:** `TitleCard.png` from each piece folder, letterboxed to the audience
  display, alpha-blended from black over `fadeSeconds`.
- Everything is driven by **showrunner.json**. No code change needed to reorder.

## EDIT THE SHOW — showrunner.json

```jsonc
{
  "showRoot": "/Users/lionelyu/Music/Belgium Concert Program",
  "audioDeviceName": "Audient",   // loose match; change if device name differs
  "fadeSeconds": 1.0,             // title fade in/out time
  "audienceDisplayIndex": 1,      // 0 = your laptop screen, 1 = projector
  "backingChannels": [1, 2],      // device outputs for FOH
  "clickChannels": [3, 4],        // device outputs for in-ears
  "pieces": [
    { "order": "6", "title": "Canon in Dream",
      "subtitle": "Remix of Pachelbel's Canon in D",
      "folder": "06 - Canon in Dream (EDM)",
      "titleCard": "TitleCard.png",
      "hasAudio": true, "backing": "Backing.wav", "click": "Click.wav" }
    // ...15 pieces total, already filled in
  ]
}
```

To **reorder**: rearrange the objects in `"pieces"`.
To **add a piece**: copy a block, point it at a folder, set `hasAudio`.
To **drop the projector title** for a piece: it still needs a `titleCard` path,
but you can point it at a black PNG, or just don't worry about it.

## VENUE DEBUGGING (the whole point of owning this)

**No sound / wrong outputs:**
1. `python3 showrunner.py --list-devices` — find the line with "Audient" and note
   its output channel count (must be ≥4). If it's not there, the interface isn't
   connected / powered.
2. If the name isn't exactly "Audient", set `"audioDeviceName"` in the JSON to a
   word that appears in the real name (e.g. "iD44").
3. Backing should come from the PA (outs 1-2); click only in your ears (outs 3-4).
   If they're swapped, swap `backingChannels` and `clickChannels` in the JSON.

**Title card not on the projector / on the wrong screen:**
1. `python3 showrunner.py --list-displays` — note which index is the projector.
2. Set `"audienceDisplayIndex"` to that number. (0 is usually the laptop.)
3. If geometry looks off, run `--windowed` to confirm the card itself renders,
   then sort the display separately.

**App won't start / crashes:** read `showrunner.log` (written next to the script).
The last lines show the error. Most issues are a missing `pip3` library or the
interface not plugged in.

**Nuclear fallback:** if anything about the title cards misbehaves at the venue,
run the audio from this app and put the 15 `TitleCard.png` files in **Keynote**
(one per slide, black background) on the projector and arrow through them. The
audio engine is the irreplaceable part; titles can always go in Keynote.

## LIMITS (honest)

- Title fades are CPU alpha-blends (Pillow). At 1080p they're smooth on an M-series
  Mac; if you ever see a stutter, lower `fadeSeconds` or pre-render fade clips.
- This debuts at a live show — **rehearse a full run at home once** before the
  venue, ideally with the Audient connected so `--selftest` passes for real.
