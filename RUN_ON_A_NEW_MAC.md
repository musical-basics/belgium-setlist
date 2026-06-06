# Run ShowRunner on a new Mac

A self-contained, copy-paste guide to get ShowRunner playing on a Mac that has never seen it
before. Takes ~5 minutes. (For what the app does and how to operate it, see
[ShowRunnerApp/README.md](ShowRunnerApp/README.md).)

---

## 0. What you need

- A Mac running **macOS 13 (Ventura) or newer**.
- The **Audient iD44** (or any audio interface with **≥ 4 output channels**). Built-in speakers
  work too, but the click can't be separated — you'd only get the backing track.
- The **`ShowAudio` folder** — the single bundle of audio files that aren't in git (see step 3).
  Bring it on a USB stick, in Dropbox, or AirDrop it from the other Mac.
- An internet connection for the first build.

You do **not** need Xcode, an Apple Developer account, or any paid software.

---

## 1. Install Command Line Tools (one-time)

This gives you the `swift` compiler. Run it once per Mac:

```bash
xcode-select --install
```

A dialog pops up — click **Install** and wait for it to finish. If it says
"command line tools are already installed", you're good.

> Check it worked: `swift --version` should print a version (5.9 or newer).

---

## 2. Clone the project

```bash
cd ~                       # or wherever you want it (e.g. inside Dropbox)
git clone https://github.com/musical-basics/belgium-setlist.git
cd belgium-setlist
```

This already contains everything **except the audio**: the app source, all 15 **title cards**,
the **running order**, and your **saved volume levels** (`showrunner.json`).

---

## 3. Drop in the `ShowAudio` folder

This one folder holds every file that isn't in git — the backing/click WAVs for the 5 EDM pieces.
Copy the **whole `ShowAudio` folder** into the `belgium-setlist` folder, right next to
`showrunner.json`:

```
belgium-setlist/
├── showrunner.json
├── ShowRunnerApp/
├── 01 - Rachmaninoff Prelude G minor/  (title card, from git)
├── …
└── ShowAudio/        ← paste this whole folder here
    ├── 04 - Torrent Etude (EDM)/Backing.wav, Click.wav
    ├── 06 - Canon in Dream (EDM)/…
    └── …
```

That's the entire "transfer the audio" step. ShowRunner automatically reads the WAVs out of
`ShowAudio/`, so you don't place anything into the individual piece folders.

---

## 4. Build the app

The repo ships **source code**, not the finished app — so build it once (and again any time you
change the code):

```bash
cd ShowRunnerApp
./build.sh
```

This creates **`ShowRunner.app`** in the project folder, right next to `showrunner.json`.
The app finds its config relative to itself, so it works no matter where you cloned it or what
your macOS username is.

---

## 5. Pre-flight check (do this before every show)

Confirms the audio device is present, all title cards exist, and every backing/click pair loads
and routes correctly — **without opening any windows**:

```bash
swift run -c release ShowRunner --selftest
```

Look for **`RESULT: PASS ✅`** at the bottom. If a WAV is missing or in the wrong place, it's
listed with a ❌ so you know exactly what to fix.

---

## 6. Run it

- **Plug in the Audient iD44** (or your interface).
- **Double-click `ShowRunner.app`** in Finder (it's in the `belgium-setlist` folder), or:
  ```bash
  open ../ShowRunner.app
  ```
- In the window: pick your **Audio device**, **Audience display**, and **Backing → / Click →
  output pairs** from the dropdowns if they aren't already right. Set your master levels.
- **Press Space to fire the selected piece.**

### Keys
| Key | Action |
|-----|--------|
| **Space** / **Enter** | GO — fire the selected piece |
| **↑ / ↓** | Move selection (does not fire) |
| **Esc** | STOP / PANIC |
| **[** / **]** | Backing master volume −/+ |
| **−** / **=** | Click master volume −/+ |

---

## Troubleshooting

**"I launched it but there's no window."**
It opened behind a full-screen app on another Space. Press **⌘-Tab → ShowRunner**, click its
**Dock icon**, or swipe to the desktop. (The app tries to force itself to the front, so this is rare.)

**A piece shows red / "MISSING".**
That piece's title card or WAV isn't where it should be. Run `--selftest` (step 5) — it tells you
the exact missing file. Usually it means the `ShowAudio` folder wasn't copied into the project
folder (step 3), or it landed one level too deep.

**No sound on an EDM piece / "device has <4 outputs".**
The selected device can't carry the click. Plug in the iD44 and pick it (and the output pairs)
from the dropdowns. EDM playback is blocked on the wrong device on purpose, so you never blast
the backing out the wrong output.

**`./build.sh` fails with "swift: command not found" or an `xcrun` error.**
Command Line Tools aren't installed — go back to step 1.

**It built on the old Mac but won't run here.**
Don't copy `ShowRunner.app` between Macs — **build it on each Mac** (step 4). A locally-built app
runs without Gatekeeper warnings; a copied one may be blocked.

**Where are the logs?**
`~/Library/Logs/ShowRunner/showrunner.log` — every launch, GO, STOP, and error is recorded there.

---

## Quick reference (the whole thing in one block)

```bash
xcode-select --install                       # one-time, then click Install
git clone https://github.com/musical-basics/belgium-setlist.git
cd belgium-setlist
# …copy the whole "ShowAudio" folder into this folder (next to showrunner.json)…
cd ShowRunnerApp && ./build.sh               # makes ../ShowRunner.app
swift run -c release ShowRunner --selftest   # expect RESULT: PASS ✅
open ../ShowRunner.app                        # …or double-click it in Finder
```
