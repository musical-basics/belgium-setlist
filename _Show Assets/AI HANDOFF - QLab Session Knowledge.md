# AI Handoff: QLab 5 Editing Knowledge (Belgium Concert)
*Session date: 2026-06-05 · Machine: Lionel's Mac Studio · QLab 5.3.3 (build 5303)*
*Audience: a future AI assistant (or human tech) continuing this work.*

---

## 1. CURRENT STATE (what's done, what's pending)

**Workspace:** `/Users/lionelyu/Music/Belgium Concert Program/Belgium Show.qlab5`
70 cues, 1 cue list, 15 piece groups (numbered 1–12, E1–E3). Built by
`_Show Assets/Build QLab Show v2.applescript`, then hand-corrected (see §5).

- Audio Output **Patch 1 = Audient iD44 (24 Out) @ 44100 Hz** — set and verified.
- Lionel enabled the QLab **Audio license** mid-session (free tier = only 2 output
  channels; the license unlocked the full 24-out matrix). A **Video license is
  NOT active** — all Text/Titles/Fade-geometry cues show red ✗ with tooltip
  "license required… video geometry". Audio cues are unaffected.
- **CLICK cues routed to ears (outs 3-4), verified by inspection** on:
  Für Elise (cue 55 — Lionel did this one by hand, it's the reference),
  Moonlight (41), Canon in Dream (27), Still D.R.E. (66).
- **BACKING cues:** left at QLab default routing (diagonal in1→out1, in2→out2)
  which correctly feeds FOH outs 1-2 only. Do NOT touch them.
- **Torrent Etude (cues 16/17):** NO audio files yet (Lionel will export
  Backing.wav + Click.wav from Ableton into `04 - Torrent Etude (EDM)/`).
  Cue 17's levels were accidentally scrambled then reset to **defaults**.
  ⚠ When the files arrive: re-target both cues, then apply the click routing
  recipe (§4) to cue 17.
- Canon in Dream playback **tested live**: backing audio reached iD44 outs 1-2
  (meters lit). Click-to-ears not yet ear-verified — needs physical monitors
  on outs 3-4.
- ⚠ **Canon sync flag:** Backing.wav = 291.38 s, Click.wav = 291.31 s (0.07 s
  difference; files bounced 6 months apart). Probably tail padding, but fire
  the Canon group once and listen for flam before trusting it on stage.

## 2. QLAB 5 LEVELS MODEL (the thing everyone gets wrong)

The Levels tab has TWO layers; **both** must pass signal:

```
file inputs → [crosspoint matrix] → [output faders 1..N] → device outs
```

- **Crosspoints**: which input feeds which output. Default for a stereo file:
  in1→out1 = 0 dB, in2→out2 = 0 dB, everything else unset (-INF).
- **Output faders**: per-output trim after the crosspoints. Default all at 0.
- Consequence proven empirically this session: pulling faders 1-2 down WITHOUT
  adding crosspoints to 3-4 = **total silence** (signal has no path). The
  working click recipe needs BOTH edits (§4).
- An **untargeted** Audio cue (no file) renders a generic multi-input matrix
  (rows 1,2,3,4…) whose cell grid is laid out differently → don't preset
  levels on placeholder cues; the clicks land in wrong cells. Set levels only
  after the file target exists.
- "Set Default Levels" button = clean reset (diagonal crosspoints, faders 0).
- Patch volume limits (Workspace Settings → Audio): Max +12 dB, **Min -60 dB —
  values at/below -60 are treated/displayed as -INF**. So scripting `db -120`
  reads back as `-60`. Not a bug.

## 3. APPLESCRIPT: WHAT WORKS, WHAT BIT US

- App id: `com.figure53.QLab.5`. Workspace addressing:
  `tell application id "com.figure53.QLab.5" to tell front workspace`.
- The official, supported automation path is AppleScript/OSC. The `.qlab5`
  FILE FORMAT IS PROPRIETARY: outer NSKeyedArchiver binary plist; the cue data
  is a **nested binary plist** inside the `cueLists` value's `NS.data`. We
  successfully READ it with Python plistlib (see §6) — do not attempt to WRITE
  one by hand.
- `setLevel row R column C db X` / `getLevel row R column C`:
  per Figure 53 docs, **row = output (0 = main), column = input (0 = main)**.
  - `row N column 0` = output fader N
  - `row N column M` = crosspoint input M → output N
  - Empirically verified: `setLevel row 5 column 0 db -120` changed output
    fader 5 (read back -60 due to the volume floor).
- **`v` (preview) on a selected cue plays it; `cmd+period` is panic/stop-all.**
  Escape did NOT reliably stop playback in our tests. Double-clicking a cue
  row opens the name editor (Edit mode), it does NOT fire the cue.
- Group modes: AppleScript `set mode of theGroup to timeline` works (= "start
  all children simultaneously"). Munich raw values: 3 = timeline, 1 =
  sequential playthrough wrapper, 0 = the cue list itself.
- Newly `make`-d cues are auto-selected → grab via
  `last item of (selected as list)`. Moving into groups requires uniqueID:
  `move cue id <id> of <parent> to end of <group>`.
- ⚠ **THE BIG GOTCHA — stale Script Editor buffers.** Script Editor does NOT
  reload a file changed on disk; it keeps its old buffer and marks the title
  "Edited". We ran what we thought was a corrected script but Script Editor
  executed the stale version (its success dialog even lied to us). ALWAYS
  close the window and reopen the file fresh after editing the .applescript
  on disk. Verify by reading the on-screen code before clicking Run.
- ⚠ `try` blocks swallow routing errors silently — during build, license
  limits made all >2-channel setLevel calls fail invisibly. For diagnosis,
  write probe scripts with NO try blocks and `display dialog` the read-backs.
- .applescript text files saved/reopened by Script Editor may be re-encoded
  UTF-16; fancy chars (¬ continuations, é/ü, —, ·) can corrupt. If a script
  won't compile, regenerate it with plain ASCII where possible.

## 4. THE CLICK-ROUTING RECIPE (proven, use for any new click cue)

Goal: click to in-ears (iD44 outs 3-4), nothing to FOH (outs 1-2).
Reference implementation: cue 55 (Lionel's hand-made example).

In the cue's **Levels** tab (Audio license must be active):
1. Drag **output fader 1** to the bottom (-INF).
2. Drag **output fader 2** to the bottom (-INF).
3. Double-click crosspoint cell **row "1" / column "3"**, type `0`, Return.
4. Double-click crosspoint cell **row "2" / column "4"**, type `0`, Return.
Leave faders 3-12 up and main at 0. Done.

BACKING cues need nothing — default diagonal already = outs 1-2 only.

## 5. HISTORY OF THE ROUTING BUG (so you don't re-fight it)

1. Build script v2 ran while QLab was on the FREE tier (2-out limit) → its
   crosspoint/silencing setLevel calls on channels 3+ failed silently inside
   try blocks → all audio cues ended up with DEFAULT levels.
2. Lionel bought/enabled the Audio license → full 24-out matrix appeared,
   all faders showing 0 (defaults), nothing routed to 3-4.
3. A "Fix Audio Routing.applescript" was written; first run executed a STALE
   buffer (see §3 gotcha) → no effect despite success dialog.
4. Lionel demonstrated the manual fix on cue 55; recipe (§4) was replicated
   via UI automation on cues 41, 27, 66. Cue 17 (Torrent, untargeted)
   deferred to when its audio exists.
- `_Show Assets/Fix Audio Routing.applescript` (corrected orientation) exists
  but was never verified end-to-end after the buffer fiasco — prefer the
  manual recipe or re-verify the script with read-backs before trusting it.

## 6. READING .qlab5 FILES PROGRAMMATICALLY (read-only!)

```python
import plistlib
data  = plistlib.load(open("Show.qlab5","rb"))      # outer archive
objs  = data["$objects"]                            # UID(n) → objs[n.data]
# find dict with key "cueLists" → its value dict has "NS.data" (bytes)
inner = plistlib.loads(<that NS.data blob>)         # nested archive = cues
# inner["$objects"] holds cue dicts: name/number/uniqueID/cues(children)/
# mode/filePath strings, level matrices as dicts {row, column, initialLevel, gang}
```
Munich workspace fully decoded this way → structure report saved at
`outputs/munich_structure.txt` (session scratch; regenerate if needed).
Munich show pattern (reused for Belgium): timeline Group per piece; media cue
at opacity 0 + Fade-in cue (1–5 s); separate manual Fade-out (often
stop-target-when-done); titles = native Titles cues (Futura-Bold 48/24pt).

## 7. COMPUTER-USE / UI AUTOMATION NOTES (this machine)

- request_access works by **bundle ID** more reliably than display names:
  `com.figure53.QLab.5`, `com.apple.finder`, `com.apple.ScriptEditor2`.
  (Display name "QLab 5" fails; "QLab" was also flaky.)
- Script Editor is tier "click": you may CLICK (Run button = ▶ in toolbar)
  but cannot type/right-click into it. Author scripts on disk with file
  tools, then open via Finder (Cmd+Shift+G → path → Cmd+O) and click Run.
- "Default Folder X" utility owns parts of save dialogs → clicks there get
  blocked; use **Return** to accept the default Save button instead.
- cmd+tab is blocked without the systemKeyCombos grant; use open_application.
- QLab Levels panel geometry (window at its current position): output fader
  knobs top ≈ y 523, bottom ≈ y 572; fader 1 x≈980, fader 2 x≈999 (narrow
  hitbox — retry at ±1 px if a drag doesn't take); crosspoint row1 y≈609,
  row2 y≈620, col3 x≈1019, col4 x≈1039. ALWAYS re-zoom to verify after edits;
  drags/double-clicks silently miss ~20% of the time.
- Zoom screenshots capture pre-batch frames — you cannot see live audio
  meters inside a batch zoom. To verify playback, take a plain screenshot
  while the cue is running.

## 8. REMAINING TODO (concert: Thu 11 June 2026, 19u30, CC De Factorij)

- [ ] Torrent Etude: Lionel exports Backing.wav + Click.wav from Ableton →
      drop in `04 - Torrent Etude (EDM)/` → re-target cues 16/17 → apply §4
      recipe to cue 17.
- [ ] Ear-verify click on outs 3-4 (plug in-ears into iD44 3-4, preview a
      CLICK cue).
- [ ] Canon in Dream: fire the full group; listen for backing/click flam
      (0.07 s file-length mismatch).
- [ ] Video license: install/activate on this machine or the show MacBook,
      else title cues won't render. Then Workspace Settings → Video → assign
      projector to the stage.
- [ ] At venue: re-check Patch 1 still points at the iD44 (device patches can
      reset if hardware was absent at launch); test tone outs 1-2 → FOH,
      3-4 → ears.
- [ ] Decide pick-one (Winter Wind vs Fight for Freedom) + tentative encores;
      timing model says full show ≈ 80–86 min vs a 75–90 min window (fits).
- [ ] Setlist tracker: `Belgium_Concert_Setlist.xlsx` (Setlist/Files/Timing
      tabs) — keep updating the Files tab as folders fill.

## 9. KEY FILE MAP

```
Belgium Concert Program/
├── Belgium Show.qlab5                  ← THE show file (save after edits!)
├── Belgium_Concert_Setlist.xlsx        ← tracker (3 tabs)
├── Munich Qlab.qlab5                   ← reference workspace (read-only)
├── Backing Tracks/All Backing Laptop/  ← source WAVs (incl. unused versions)
├── 01..12, E1..E3, B1..B5 folders      ← per-piece assets; EDM folders have
│                                          Backing.wav + Click.wav (04 empty)
│                                          + TitleCard.png in every piece folder
└── _Show Assets/
    ├── Build QLab Show v2.applescript  ← built the workspace (already run)
    ├── Fix Audio Routing.applescript   ← unverified post-fix; prefer §4 manual
    ├── Probe Levels.applescript        ← diagnostic template (no try blocks)
    ├── QLAB SETUP README.md            ← human-facing setup steps
    ├── Black.png                       ← blank projector slide
    └── AI HANDOFF - ... (this file)
```
