-- Fix routing on all BACKING/CLICK audio cues, now that the Audio
-- license unlocks the full output matrix.
-- QLab levels matrix convention (per official docs):
--   setLevel row R column C  ->  R = OUTPUT (0 = main), C = INPUT (0 = main)
--   So: row N column 0  = output fader N
--       row N column M  = crosspoint input M -> output N
-- BACKING cues -> outputs 1-2 only. CLICK cues -> outputs 3-4 only.

tell application id "com.figure53.QLab.5" to tell front workspace
	repeat with theGroup in (cues of first cue list as list)
		try
			if q type of theGroup is "Group" then
				repeat with childCue in (cues of theGroup as list)
					my fixIfAudio(childCue)
				end repeat
			else
				my fixIfAudio(theGroup)
			end if
		end try
	end repeat
	display dialog "Routing repaired: BACKING -> outs 1-2, CLICK -> outs 3-4, all other outputs silenced." buttons {"OK"} default button "OK"
end tell

on fixIfAudio(theCue)
	tell application id "com.figure53.QLab.5" to tell front workspace
		try
			if q type of theCue is "Audio" then
				set theName to q name of theCue
				if theName contains "BACKING" then
					my route(theCue, 1, 2)
				else if theName contains "CLICK" then
					my route(theCue, 3, 4)
				end if
			end if
		end try
	end tell
end fixIfAudio

on route(theCue, outL, outR)
	tell application id "com.figure53.QLab.5" to tell front workspace
		try
			-- main fader at 0 dB
			theCue setLevel row 0 column 0 db 0
			-- silence ALL output faders 1..16, then open the wanted pair
			repeat with o from 1 to 16
				theCue setLevel row o column 0 db -120
			end repeat
			theCue setLevel row outL column 0 db 0
			theCue setLevel row outR column 0 db 0
			-- crosspoints: silence inputs 1-2 to all outputs, then set the pair
			repeat with o from 1 to 16
				theCue setLevel row o column 1 db -120
				theCue setLevel row o column 2 db -120
			end repeat
			theCue setLevel row outL column 1 db 0
			theCue setLevel row outR column 2 db 0
		end try
	end tell
end route
