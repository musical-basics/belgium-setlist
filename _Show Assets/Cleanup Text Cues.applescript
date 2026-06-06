-- Cleanup pass v2. KEY FIX: cues must be deleted/moved THROUGH their
-- enclosing group, not via a workspace-level reference. Addressing
-- `delete c` where c came from `first cue whose...` errors with
-- "You cannot move/insert/remove cues referenced from a workspace."
-- Correct: iterate the group's own children and delete by index/ref
-- within that group context.
--
-- For each piece group: re-point ALL Fade cues to the group's Video cue,
-- then delete every Text cue child (addressed via the group).

property folderMap : {"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "E1", "E2", "E3"}

tell application id "com.figure53.QLab.5" to tell front workspace
	set delTxt to 0
	repeat with theNum in folderMap
		try
			set grp to (first cue whose q number is theNum)
			-- find the Video cue's id (the keeper)
			set vidID to missing value
			repeat with c in (cues of grp as list)
				if q type of c is "Video" then set vidID to uniqueID of c
			end repeat
			-- re-point every Fade in this group to the Video cue
			if vidID is not missing value then
				repeat with c in (cues of grp as list)
					try
						if q type of c is "Fade" then set cue target of c to (first cue of grp whose uniqueID is vidID)
					end try
				end repeat
			end if
			-- delete Text cues, addressed THROUGH the group.
			-- loop until none remain (deleting shifts the list).
			set keepGoing to true
			repeat while keepGoing
				set keepGoing to false
				set kids to (cues of grp as list)
				repeat with i from 1 to count of kids
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
	display dialog ("Text cues deleted: " & delTxt) buttons {"OK"} default button "OK"
end tell
