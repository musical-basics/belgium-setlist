-- Map Torrent Etude audio into cues 16 (BACKING) and 17 (CLICK),
-- then route: BACKING -> outs 1-2, CLICK -> outs 3-4 (ears).
-- Files already placed in "04 - Torrent Etude (EDM)/".

property BASE : "/Users/lionelyu/Music/Belgium Concert Program/04 - Torrent Etude (EDM)/"

tell application id "com.figure53.QLab.5" to tell front workspace
	-- BACKING -> cue 16
	set backCue to first cue whose q number is "16"
	set file target of backCue to POSIX file (BASE & "Backing.wav")
	my route(backCue, 1, 2)
	-- CLICK -> cue 17
	set clickCue to first cue whose q number is "17"
	set file target of clickCue to POSIX file (BASE & "Click.wav")
	my route(clickCue, 3, 4)
	display dialog "Torrent mapped: 16=Backing (outs 1-2), 17=Click (outs 3-4)." buttons {"OK"} default button "OK"
end tell

-- route a stereo file to a specific output pair; silence everything else.
-- QLab matrix: row = OUTPUT (0=main), column = INPUT (0=main).
on route(theCue, outL, outR)
	tell application id "com.figure53.QLab.5" to tell front workspace
		theCue setLevel row 0 column 0 db 0
		-- silence output faders 1..16
		repeat with o from 1 to 16
			theCue setLevel row o column 0 db -120
		end repeat
		theCue setLevel row outL column 0 db 0
		theCue setLevel row outR column 0 db 0
		-- crosspoints: silence inputs 1-2 to all outs, then open the pair
		repeat with o from 1 to 16
			theCue setLevel row o column 1 db -120
			theCue setLevel row o column 2 db -120
		end repeat
		theCue setLevel row outL column 1 db 0
		theCue setLevel row outR column 2 db 0
	end tell
end route
