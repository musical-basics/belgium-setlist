-- DEFINITIVE title-card conversion. Per piece group:
--   1. If no Video cue exists, create one targeting TitleCard.png (opacity 0),
--      addressed/moved THROUGH the group.
--   2. Re-point every Fade cue in the group to the Video cue.
--   3. Delete every Text cue in the group (delete cue i OF grp — the only
--      form QLab allows; workspace-level delete throws an error).
-- Idempotent.

property BASE : "/Users/lionelyu/Music/Belgium Concert Program/"
property folderMap : {¬
	{"1", "01 - Rachmaninoff Prelude G minor"}, {"2", "02 - Colors of the Soul"}, ¬
	{"3", "03 - Gallop (Trio)"}, {"4", "04 - Torrent Etude (EDM)"}, ¬
	{"5", "05 - Beethoven Virus (Trio)"}, {"6", "06 - Canon in Dream (EDM)"}, ¬
	{"7", "07 - Fight for Freedom (maybe)"}, {"8", "08 - Winter Wind"}, ¬
	{"9", "09 - Moonlight Sonata (EDM)"}, {"10", "10 - Sunflowers"}, ¬
	{"11", "11 - Dreams of a Violin (Duet)"}, {"12", "12 - Fur Elise Dubstep (EDM)"}, ¬
	{"E1", "E1 - Fantasie Impromptu"}, {"E2", "E2 - Flight of the Bumblebee"}, ¬
	{"E3", "E3 - Still Dre (EDM)"}}

tell application id "com.figure53.QLab.5" to tell front workspace
	set madeVid to 0
	set delTxt to 0
	repeat with pair in folderMap
		set theNum to item 1 of pair
		set theFolder to item 2 of pair
		try
			set grp to (first cue whose q number is theNum)

			-- 1. ensure a Video cue exists
			set vidID to missing value
			repeat with c in (cues of grp as list)
				if q type of c is "Video" then set vidID to uniqueID of c
			end repeat
			if vidID is missing value then
				make type "Video"
				set newVid to last item of (selected as list)
				set q name of newVid to (theFolder & " -- TITLE")
				set file target of newVid to POSIX file (BASE & theFolder & "/TitleCard.png")
				try
					set opacity of newVid to 0
				end try
				set vidID to uniqueID of newVid
				-- move into group through the cue list / parent
				set p to parent of newVid
				move cue id vidID of p to end of grp
				set madeVid to madeVid + 1
			end if

			-- 2. re-point all fades to the Video cue
			repeat with c in (cues of grp as list)
				try
					if q type of c is "Fade" then set cue target of c to (first cue of grp whose uniqueID is vidID)
				end try
			end repeat

			-- 3. delete Text cues, addressed through the group
			set keepGoing to true
			repeat while keepGoing
				set keepGoing to false
				set kids to (cues of grp as list)
				repeat with i from 1 to (count of kids)
					if q type of (item i of kids) is "Text" then
						delete (cue i of grp)
						set delTxt to delTxt + 1
						set keepGoing to true
						exit repeat
					end if
				end repeat
			end repeat
		end try
	end repeat
	display dialog ("Done. Image cues created: " & madeVid & "  ·  Text cues deleted: " & delTxt) buttons {"OK"} default button "OK"
end tell
