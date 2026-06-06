-- Swap each piece's Text title cue for a VIDEO cue targeting TitleCard.png
-- (free-tier-safe: image display needs no license, unlike Titles geometry).
-- For each top-level Group:
--   1. find the existing Text cue (the "Ñ TITLE" child)
--   2. make a Video cue, target it at <folder>/TitleCard.png, opacity 0
--   3. move it into the group, just after where the Text cue was
--   4. re-point any Fade cues that targeted the Text cue -> the Video cue
--   5. delete the Text cue
-- Folder is derived from the group's cue number via the same list used to build.

property BASE : "/Users/lionelyu/Music/Belgium Concert Program/"

-- {cue number, folder name}
property folderMap : {Â
	{"1", "01 - Rachmaninoff Prelude G minor"}, Â
	{"2", "02 - Colors of the Soul"}, Â
	{"3", "03 - Gallop (Trio)"}, Â
	{"4", "04 - Torrent Etude (EDM)"}, Â
	{"5", "05 - Beethoven Virus (Trio)"}, Â
	{"6", "06 - Canon in Dream (EDM)"}, Â
	{"7", "07 - Fight for Freedom (maybe)"}, Â
	{"8", "08 - Winter Wind"}, Â
	{"9", "09 - Moonlight Sonata (EDM)"}, Â
	{"10", "10 - Sunflowers"}, Â
	{"11", "11 - Dreams of a Violin (Duet)"}, Â
	{"12", "12 - Fur Elise Dubstep (EDM)"}, Â
	{"E1", "E1 - Fantasie Impromptu"}, Â
	{"E2", "E2 - Flight of the Bumblebee"}, Â
	{"E3", "E3 - Still Dre (EDM)"} Â
		}

on folderFor(theNum)
	repeat with pair in folderMap
		if item 1 of pair is theNum then return item 2 of pair
	end repeat
	return missing value
end folderFor

tell application id "com.figure53.QLab.5" to tell front workspace
	set doneCount to 0
	repeat with pair in folderMap
		set theNum to item 1 of pair
		set theFolder to item 2 of pair
		try
			set grp to (first cue whose q number is theNum)
			-- locate the Text cue inside this group
			set txtCue to missing value
			repeat with c in (cues of grp as list)
				if q type of c is "Text" then
					set txtCue to c
					exit repeat
				end if
			end repeat
			if txtCue is not missing value then
				set txtID to uniqueID of txtCue
				set txtName to q name of txtCue
				
				-- make the Video cue
				make type "Video"
				set vid to last item of (selected as list)
				set q name of vid to txtName
				set file target of vid to POSIX file (BASE & theFolder & "/TitleCard.png")
				try
					set opacity of vid to 0
				end try
				set vidID to uniqueID of vid
				-- move into the group
				set vParent to parent of vid
				move cue id vidID of vParent to end of grp
				
				-- re-point any Fade cues in the group that targeted the Text cue
				repeat with c in (cues of grp as list)
					try
						if q type of c is "Fade" then
							if uniqueID of (cue target of c) is txtID then
								set cue target of c to (first cue whose uniqueID is vidID)
							end if
						end if
					end try
				end repeat
				
				-- delete the old Text cue
				delete (first cue whose uniqueID is txtID)
				set doneCount to doneCount + 1
			end if
		end try
	end repeat
	display dialog ("Swapped " & doneCount & " title cards from Text to Video (TitleCard.png).") buttons {"OK"} default button "OK"
end tell
