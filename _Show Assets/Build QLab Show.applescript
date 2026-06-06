-- ============================================================
-- BELGIUM CONCERT - QLab 5 Show Builder
-- Lionel Yu · CC De Factorij · 11 June 2026
--
-- WHAT THIS DOES
--   Builds the full show in the FRONT workspace of QLab 5:
--   · For EVERY piece: a Group cue containing a title-card
--     Video cue (TitleCard.png from the piece folder).
--   · For EDM pieces: the group also gets TWO Audio cues —
--     Backing (routed to outputs 1-2, FOH) and Click (routed
--     to outputs 3-4, in-ears) — fired simultaneously with
--     the title card ("start all children simultaneously").
--
-- BEFORE RUNNING
--   1. Open QLab 5 with a NEW empty workspace in front.
--   2. In Workspace Settings > Audio, confirm your Audient
--      interface is the device on Audio Output Patch 1.
--   3. Edit BASE below if your folder lives elsewhere.
--   4. Audio files this script expects in each EDM folder:
--        Backing.wav   and   Click.wav
--      (If a file is missing, the cue is still created and
--       shows as a broken target — drop the file in later and
--       re-target, or re-run this script.)
--
-- ROUTING (matches your Ableton session)
--   Backing: in 1→out 1, in 2→out 2     (FOH stereo)
--   Click:   in 1→out 3, in 2→out 4     (monitor/in-ears)
--   Crosspoints to unused outs set to -120 dB.
-- ============================================================

property BASE : "/Users/lionelyu/Music/Belgium Concert Program/"

-- {folder, cue number, display name, isEDM}
property pieceList : {¬
	{"01 - Rachmaninoff Prelude G minor", "1", "Rachmaninoff Prelude in G minor", false}, ¬
	{"02 - Colors of the Soul", "2", "Colors of the Soul", false}, ¬
	{"03 - Gallop (Trio)", "3", "Gallop (Trio)", false}, ¬
	{"04 - Torrent Etude (EDM)", "4", "Torrent Etude Nightmare", true}, ¬
	{"05 - Beethoven Virus (Trio)", "5", "Beethoven Virus (Trio)", false}, ¬
	{"06 - Canon in Dream (EDM)", "6", "Canon in Dream", true}, ¬
	{"07 - Fight for Freedom (maybe)", "7", "Fight for Freedom", false}, ¬
	{"08 - Winter Wind", "8", "Winter Wind Etude", false}, ¬
	{"09 - Moonlight Sonata (EDM)", "9", "Moonlight Sonata Nightmare", true}, ¬
	{"10 - Sunflowers", "10", "Sunflowers", false}, ¬
	{"11 - Dreams of a Violin (Duet)", "11", "Dreams of a Violin (Duet)", false}, ¬
	{"12 - Fur Elise Dubstep (EDM)", "12", "Fur Elise Nightmare", true}, ¬
	{"E1 - Fantasie Impromptu", "E1", "Fantaisie-Impromptu", false}, ¬
	{"E2 - Flight of the Bumblebee", "E2", "Flight of the Bumblebee", false}, ¬
	{"E3 - Still Dre (EDM)", "E3", "Still D.R.E.", true} ¬
		}

on run
	tell application id "com.figure53.QLab.5" to tell front workspace
		repeat with p in pieceList
			set theFolder to item 1 of p
			set theNum to item 2 of p
			set theName to item 3 of p
			set isEDM to item 4 of p

			-- ---- Group cue for the piece ----
			make type "Group"
			set groupCue to last item of (selected as list)
			set q number of groupCue to theNum
			set q name of groupCue to theName
			try
				set mode of groupCue to timeline -- start all children together
			end try
			set groupID to uniqueID of groupCue

			-- ---- Title card video cue ----
			make type "Video"
			set vidCue to last item of (selected as list)
			set q name of vidCue to (theName & " — Title Card")
			try
				set file target of vidCue to POSIX file (BASE & theFolder & "/TitleCard.png")
			end try
			my moveIntoGroup(vidCue, groupID)

			-- ---- EDM: backing + click audio cues ----
			if isEDM then
				-- Backing → outs 1-2
				make type "Audio"
				set backCue to last item of (selected as list)
				set q name of backCue to (theName & " — BACKING (FOH 1-2)")
				try
					set file target of backCue to POSIX file (BASE & theFolder & "/Backing.wav")
				end try
				my routeStereo(backCue, 1, 2)
				my moveIntoGroup(backCue, groupID)

				-- Click → outs 3-4
				make type "Audio"
				set clickCue to last item of (selected as list)
				set q name of clickCue to (theName & " — CLICK (ears 3-4)")
				try
					set file target of clickCue to POSIX file (BASE & theFolder & "/Click.wav")
				end try
				my routeStereo(clickCue, 3, 4)
				my moveIntoGroup(clickCue, groupID)
			end if
		end repeat
		display dialog "Show built: 15 piece groups, title cards on all, backing+click on the 5 EDM pieces." buttons {"OK"} default button "OK"
	end tell
end run

-- route a stereo file: in1→outL, in2→outR, silence elsewhere
on routeStereo(theCue, outL, outR)
	tell application id "com.figure53.QLab.5" to tell front workspace
		try
			-- main level 0 dB
			theCue setLevel row 0 column 0 db 0
			-- silence all 8 device outs for both inputs first
			repeat with o from 1 to 8
				try
					theCue setLevel row o column 1 db -120
					theCue setLevel row o column 2 db -120
				end try
			end repeat
			-- open the two we want
			theCue setLevel row outL column 1 db 0
			theCue setLevel row outR column 2 db 0
		end try
	end tell
end routeStereo

on moveIntoGroup(theCue, groupID)
	tell application id "com.figure53.QLab.5" to tell front workspace
		set cueID to uniqueID of theCue
		set theParent to parent of theCue
		set theGroup to first cue whose uniqueID is groupID
		move cue id cueID of theParent to end of theGroup
	end tell
end moveIntoGroup
