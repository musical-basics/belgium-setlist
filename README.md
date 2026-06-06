# Belgium Setlist — ShowRunner

Live-concert playback for Lionel Yu's show in Zaventem, Belgium (Thu 11 June 2026).
A native macOS app, **ShowRunner**, that replaces QLab: one keypress per piece plays a
backing track to outputs 1·2 and a sample-locked click to outputs 3·4, and shows a
full-screen title card on the projector with a 1-second fade.

---

# ▶︎ HOW TO RUN IT (read this first)

## Just launch it — double-click the app
In **Finder**, open this folder (`Belgium Concert Program`) and **double-click `ShowRunner.app`**.
That's the whole thing. The control window opens with the 15-piece running order.

Full path to the app: `/Users/lionelyu/Music/Belgium Concert Program/ShowRunner.app`

- Prefer Terminal? `open "/Users/lionelyu/Music/Belgium Concert Program/ShowRunner.app"`

## Using it
| Key | Action |
|-----|--------|
| **Space** or **Enter** | **GO** — fire the selected piece (title card fades up; EDM also starts backing + click) |
| **↑ / ↓** | Move the selection up/down (does NOT fire) |
| **Esc** | **STOP / PANIC** — instant stop + fade card to black |

Quit the app with **⌘Q**.

## ⚠️ "I launched it but I don't see the window!"
It opened **behind your full-screen editor on another Space**. Do ONE of these:
- Press **⌘-Tab** and pick **ShowRunner**, or
- Click the **ShowRunner icon in the Dock**, or
- Swipe with **3–4 fingers** to the desktop Space (or exit your editor's full-screen).

The app now forces its window onto whatever Space is active, so this should be rare.

## First time, or after editing the code — rebuild the app
Open **Terminal** and run (copy-paste both lines):
```bash
cd "/Users/lionelyu/Music/Belgium Concert Program/ShowRunnerApp"
./build.sh
```
That recreates `ShowRunner.app` next to `showrunner.json`. Then double-click the app as above.
Requires Command Line Tools only (`xcode-select --install`) — **no full Xcode needed.**

## Check everything's ready before the show (no windows, just a report)
```bash
cd "/Users/lionelyu/Music/Belgium Concert Program/ShowRunnerApp"
swift run -c release ShowRunner --selftest
```
Confirms the Audient iD44 is found with ≥4 outputs, every title card exists, and all 5 EDM
backing/click pairs load and route to outs 1·2 / 3·4. Look for `RESULT: PASS ✅`.

---

> More detail (audio design, config, reliability): **[ShowRunnerApp/README.md](ShowRunnerApp/README.md)**

## What's in this repo

| Tracked in git | Not in git (too big — see below) |
|---|---|
| `ShowRunnerApp/` — the Swift app source | `*.wav` backing/click tracks |
| `showrunner.json` — the running order (15 pieces) | `Backing Tracks/` (Ableton project) |
| `*/TitleCard.png` — the 15 title cards | `*.qlab5` legacy QLab sessions |

## Opening this on another laptop

1. **Clone:** `git clone https://github.com/musical-basics/belgium-setlist.git`
2. **Get the audio from Dropbox.** The backing/click WAVs are not in git. Copy each piece's
   `Backing.wav` / `Click.wav` from Dropbox into the matching `NN - Piece Name/` folder
   (the folders already exist with their `TitleCard.png`). The expected files are exactly the
   ones listed in `showrunner.json` (only the 5 EDM pieces have audio).
   - Tip: if you keep this whole folder *inside* Dropbox, the WAVs sync automatically and git
     just versions the code — nothing to copy.
3. **Build & run:**
   ```bash
   cd ShowRunnerApp && ./build.sh && open ../ShowRunner.app
   ```
   Verify everything is in place first with `swift run -c release ShowRunner --selftest`.

Requires macOS 13+ and Command Line Tools (`xcode-select --install`) — no full Xcode needed.
