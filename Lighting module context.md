Context. Solo pianist plus violinist and cellist on 3 pieces. Show runs live from this Mac. Lighting is sequenced to audio and output as sACN over the network. This is the operator's first DMX show and there is one chance to get it right on the day, with a 7-hour soundcheck window for verification. Build for reliability over cleverness.
The rig (8 fixtures, 2 universes). Treat every value marked CONFIRM as provisional until the venue replies; isolate all such values in one config file so they can be changed in one place without touching show logic.
Universe 1:

Spiider 1, start address 1
Spiider 2, start address 28
Mode: CONFIRM (provisionally Robe Spiider Mode 2 "Basic", 27 channels). Build the fixture profile from the official Robe Spiider DMX chart for whichever mode the venue confirms. Do not invent channel positions.

Universe 2:

Fargo 1 addr 1, Fargo 2 addr 10, Fargo 3 addr 19, Fargo 4 addr 28, all 9-channel mode. Channel order: Red, Green, Blue, White, Dimmer, Dimmer Fine, Strobe, Color, Zoom. (This is from a verified Dutch theater patch using these exact fixtures, but mark it CONFIRM-ON-DAY.)
Dalis 1 addr 40, Dalis 2 addr 60. Mode and channel count: CONFIRM (no footprint yet, leave the profile as a stub keyed off the venue's answer).

sACN universe numbers and the Ethernet-vs-own-node connection: CONFIRM. Architect the sACN output layer so the universe numbers are config values, not hardcoded.
Architecture requirements.

Master clock per piece. For the EDM pieces, lighting state is a pure function of audio playback position. The renderer must, every frame (target 40 fps to match DMX refresh), read the current playback time and compute the full DMX output for that instant. No reliance on the operator firing cues for the EDM set.
Separate the show data from the engine. Define each piece's lighting as data (a timeline of keyframes or cue points mapped to timestamps), not as imperative code. This lets cues be edited and retimed without touching the rendering engine, and lets the agent generate timelines per piece by analyzing the audio.
Three piece templates, since the 12 pieces collapse into 3 lighting languages:

SOLO (4 pieces): mostly static, piano lit clean, one cyc color per piece with slow drift, movers parked. 2 to 3 state changes per piece. Cue-advance is fine here; timecode optional.
TRIO (3 pieces): wider warm wash so all 3 players read evenly, slightly richer cyc, restrained. Cue-advance fine.
EDM (5 pieces): timecode-driven. Movement, color chases, strobe and zoom moves, beam looks, all keyed to musical structure. This is the bulk of the work.


Fixture abstraction layer. Address each fixture by logical name and semantic parameter (e.g. "Fargo1.intensity = 0.8", "Spiider1.pan = 0.5", "Cyc.color = deep_blue"), and let the profile layer translate to raw DMX channels per the confirmed modes. This is what makes the CONFIRM values changeable in one place: when the venue says the Spiider is a different mode, only the profile translation changes, not a single cue.
Global blackout and a manual override. One control that kills all output instantly, and a way to manually hold or advance if timecode drifts. Safety net for live.

EDM pieces, the priority work. For each of the 5 EDM tracks:

Analyze the audio file for structure: intro, builds, drops, breakdowns, outro. Detect onset/beat grid and the big energy transitions (the drops especially, since the lighting must peak with them).
Build a timecoded lighting timeline that maps musical sections to lighting behavior. Drops get the biggest moves (movers sweeping, full-intensity color hits, strobe accents, zoom punches on the Fargos). Builds ramp intensity and movement speed. Breakdowns pull back to the cyc and a soft wash. Intros and outros are minimal.
Color should follow the emotional arc of each track; pick a palette per piece and vary intensity and saturation through it rather than rainbow-cycling.
The two Spiiders are the movement engine: program symmetrical and mirrored pan/tilt so they read as intentional, not random. Keep pan/tilt smooth (16-bit if the confirmed mode exposes fine channels) and time movement changes to section boundaries.
Keep the strobe disciplined: accent on drops, never gratuitous. Note the venue has a 95 dB SPL limit but that's audio; no lighting limit, but tasteful beats constant.

Solo and trio pieces. Lighter touch. Build the SOLO and TRIO templates first as reusable looks, then instantiate per piece with a chosen cyc color and intensity. A handful of cue points each. Don't over-light the quiet pieces; restraint is the point.
Build order (do in this sequence).

Build the config file with all CONFIRM values as named constants, and the fixture profiles (Spiider, Fargo, Dalis) translating logical parameters to DMX channels per the charts.
Build the sACN output layer. Validate it can send a frame to one universe.
PROOF OF LIFE: drive a single Fargo to full white, then fade it, purely to confirm the Mac emits valid sACN that a fixture obeys. Nothing else proceeds until this works. (On the day, this is also the first soundcheck test.)
Build the master clock and the per-frame renderer reading playback position.
Build one EDM piece end to end as the reference implementation. Get it looking right against its audio.
Clone the pattern to the other 4 EDM pieces.
Build SOLO and TRIO templates, instantiate the 7 non-EDM pieces.
Build the blackout and manual override controls.

Leave these as clearly-marked config stubs for the venue's reply:

Spiider mode and channel count (and therefore the Spiider profile)
Dalis mode, channel count, and profile
The two sACN universe numbers
Fargo channel order (verify on day)
Whether output goes to the network directly or through an own node (affects only network target config, not show logic)

Critical correctness note. The fixture profiles in this app must exactly match the modes the venue sets on the physical fixtures, channel for channel. A mismatch produces garbage output that looks like a bug but isn't. Build every profile directly from the official DMX chart for the confirmed mode. When the venue confirms modes, re-verify each profile against the chart before trusting it.
