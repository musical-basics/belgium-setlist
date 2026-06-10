# CLAUDE.md — project guidance

## Workflow
- **Commit and push after every change.** After completing any change, `git add` the
  relevant files, commit with a clear message, and `git push` to `origin main`. Don't batch
  unrelated changes or leave work uncommitted.

## What this repo is
Live-concert playback for Lionel Yu's show in Zaventem, Belgium. The native macOS app
**ShowRunner** (in `ShowRunnerApp/`) plays a backing track to outs 1·2 and a sample-locked
click to outs 3·4 per piece, and shows a full-screen title card on the projector.

## Running order & folders
- The running order lives in **`showrunner.json`** — the order of the `pieces` array (plus the
  `order` label) IS the show order. To reorder, move array entries; nothing else.
- Piece **folders are named by piece, not by order** (alphabetical on disk). Each piece's
  `folder` field points at its folder, which holds `TitleCard.png` (and, for EDM pieces,
  the audio falls back to `ShowAudio/<folder>/`).
- **EDM audio:** if you rename a piece folder, rename the matching `ShowAudio/<folder>/`
  subfolder too — they must match the `folder` value exactly or audio won't load.
- Human-facing schedule docs: `Concert Schedule.md` and `Lighting & Video Cues.md`.

## Before risky edits
- Back up files you rewrite into `backup/` first.
- Legacy/unused: the QLab AppleScripts in `_Show Assets/` and the `Belgium Concert Setlist
  Python/` port are historical — the Swift app doesn't use them.
