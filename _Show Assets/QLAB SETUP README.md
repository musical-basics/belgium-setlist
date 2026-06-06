# QLab 5 Show Setup — Belgium Concert (11 June 2026)

## Why a build script instead of a ready-made .qlab5 file
The .qlab5 format is proprietary and undocumented — Figure 53's supported way to
create cues programmatically is AppleScript. This script builds the show *inside*
QLab, so the workspace is guaranteed valid, and you can re-run it any time.

## One-time setup (10 min)
1. **Audio device**: Plug in the Audient. In **QLab → Settings → Audio**, set
   Audio Output Patch 1 to the Audient (e.g. *Audient iD14/iD24/EVO*).
   Outputs 1-2 = FOH feed, outputs 3-4 = your in-ear/click feed.
   (This matches the Ableton session: backing → 1, click → 3.)
2. **Video output**: In **Settings → Video**, assign the projector as a video
   output and make sure the default video stage targets it.
3. **File names**: In each EDM piece folder, name the audio files exactly:
   - `Backing.wav`
   - `Click.wav`
   (Title cards `TitleCard.png` are already in every folder.)

## Build the show (2 min)
1. Open QLab 5 → **New Workspace** (leave it in front).
2. Open `Build QLab Show.applescript` in **Script Editor** (double-click it).
3. Press **Run** (▶). Approve the automation permission prompt the first time.
4. You'll get: 15 group cues (one per piece, numbered 1–12, E1–E3).
   - Every group: title-card Video cue.
   - EDM groups (4, 6, 9, 12, E3): + Backing cue (outs 1-2) + Click cue (outs 3-4),
     all firing together on one GO.

Missing audio files show as **broken (red) targets** — that's expected until you
drop the WAVs in. Either re-target them in QLab or just re-run the script on a
fresh workspace after the files are in place.

## Show operation
- One **GO** per piece: title card hits the projector; on EDM pieces the backing
  and click start at the same instant.
- Add a Fade/Stop cue at the end of each EDM group later if you want tails
  faded rather than running out.
- `_Show Assets/Black.png` is a full-black slide — use it as a "projector off"
  look between pieces if you want.

## Checklist before the venue
- [ ] Backing.wav + Click.wav in folders 04, 06, 09, 12, E3
- [ ] Run script → 15 groups, no red targets
- [ ] Audio patch: Audient outs 1-2 → FOH, 3-4 → in-ears (test with tone)
- [ ] Video patch: projector shows title card on GO
- [ ] Save workspace into this folder as `Belgium Show.qlab5`
