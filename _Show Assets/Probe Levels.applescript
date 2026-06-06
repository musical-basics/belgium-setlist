-- Probe 2: read levels straight off cue number 55 (Fur Elise CLICK)
-- and report how many cues matched the name search (duplicate check).

tell application id "com.figure53.QLab.5" to tell front workspace
	set wsName to its name
	set c55 to first cue whose q number is "55"
	set f5 to c55 getLevel row 5 column 0
	set f3 to c55 getLevel row 3 column 0
	set f1 to c55 getLevel row 1 column 0
	set x31 to c55 getLevel row 3 column 1
	set matchCount to count of (cues whose q name contains "CLICK (ears 3-4)" and q name contains "Elise")
	display dialog "ws=" & wsName & "  cue55 f1=" & f1 & " f3=" & f3 & " f5=" & f5 & " xpt31=" & x31 & "  nameMatches=" & matchCount buttons {"OK"} default button "OK"
end tell
