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
| **[** / **]** | Backing master volume down / up (1 dB; hold to ramp) |
| **−** / **=** | Click master volume down / up (1 dB; hold to ramp) |

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

## Setting it up on another Mac

📄 **Dedicated copy-paste guide: [RUN_ON_A_NEW_MAC.md](RUN_ON_A_NEW_MAC.md)** — start there.

Full checklist (macOS 13 or newer):

1. **Install Command Line Tools** (one-time, gives you `swift`; no full Xcode needed):
   ```bash
   xcode-select --install
   ```
2. **Clone the repo:**
   ```bash
   git clone https://github.com/musical-basics/belgium-setlist.git
   ```
   This already includes the **15 title cards**, the **running order**, and your **saved
   levels** (`showrunner.json`) — you do *not* need to transfer those.
3. **Copy the audio from Dropbox.** Only the WAVs aren't in git. Drop each piece's
   `Backing.wav` / `Click.wav` into the matching `NN - Piece Name/` folder (the folders already
   exist with their `TitleCard.png`). Only the 5 EDM pieces have audio.
   - Tip: if you clone *into* a Dropbox folder, the WAVs sync there automatically.
4. **Build the app** (the repo ships source, not the built app):
   ```bash
   cd belgium-setlist/ShowRunnerApp
   ./build.sh
   ```
   This creates `ShowRunner.app` next to `showrunner.json`. It finds its config relative to
   itself, so it works no matter where you cloned it or what your username is.
5. **Pre-flight check** — run the self-test and look for `RESULT: PASS ✅`:
   ```bash
   swift run -c release ShowRunner --selftest
   ```
   If a WAV is in the wrong place it'll be listed here.
6. **Plug in the Audient iD44** (or any interface with ≥ 4 outputs). If it's not the iD44, just
   pick your device — and your **Backing → / Click → output pairs** — from the dropdowns in the app.
7. **Double-click `ShowRunner.app`.** Pick the audience display, set your levels, hit Space.

That's the whole list. No signing/notarization, no entitlements, no extra installs — building it
locally means macOS runs it without Gatekeeper complaints.
