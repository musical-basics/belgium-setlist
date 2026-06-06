-- Minimal: try to delete the Text cue numbered "63". NO try block.
tell application id "com.figure53.QLab.5" to tell front workspace
	set c to first cue whose q number is "63"
	set t to q type of c
	delete c
	display dialog ("Deleted a cue of type: " & t) buttons {"OK"} default button "OK"
end tell
