# Belgium Setlist — ShowRunner

Live-concert playback for Lionel Yu's show in Zaventem, Belgium (Thu 11 June 2026).
A native macOS app, **ShowRunner**, that replaces QLab: one keypress per piece plays a
backing track to outputs 1·2 and a sample-locked click to outputs 3·4, and shows a
full-screen title card on the projector with a 1-second fade.

> Full app docs, keybindings, and build/run instructions: **[ShowRunnerApp/README.md](ShowRunnerApp/README.md)**

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
