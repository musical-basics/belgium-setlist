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

## Lighting
- **Read `VENUE_LIGHTING_REFERENCE.md` before touching lighting.** It has the venue's full
  fixture inventory, the FINAL patch (from `Lighting_Plot/`), every DMX channel map already
  verified against the official manufacturer charts (with the gotchas: Robe shutter open=32,
  inverted zoom, T1 CTO park=110…), the config-file map, and the measured Torrent section
  times. Don't re-research any of it.
- Engine architecture/controls/commands: `LIGHTING_README.md`. Patch + per-piece config:
  `lighting.json`. Timelines: `Timelines/*.json` — all authored (6 EDM + 5 auto-loop);
  `torrent.json` is the structural reference.

## Before risky edits
- Back up files you rewrite into `backup/` first.
- Legacy/unused: the QLab AppleScripts in `_Show Assets/` and the `Belgium Concert Setlist
  Python/` port are historical — the Swift app doesn't use them.
