extends SceneTree
## THE END-OF-BATTLE TABLE COMES DOWN AGAIN, FROM EVERY PHASE.
##
##   godot --headless --path <game> --script res://tests/final_table.gd
##
## Reported: "when the modal comes up at the end of a game, like no one won or
## whatever, it doesn't disappear. So it just stays on the screen."
##
## The rule was written as a list of the phases that should HIDE it —
## LOBBY, SETUP, BATTLE — which meant it said nothing about any phase not
## on that list. IDLE was not on it, and IDLE is exactly where a battle
## goes when it ends and no new one follows: the loop switched off, or
## the last human gone. So the table stayed up with nothing to press.
##
## The list-shaped bug is the point. This test does not check a list of
## phases somebody typed here — it READS THE PHASES OUT OF world.gd and
## requires the rule to have an answer for every one of them. Add a new
## phase to the match and this fails until the table knows about it.

## The one phase the table is for. Everything else must hide it.
const SHOWS_IN := "END"

func _initialize() -> void:
	var phases := _phases_in_world()
	# A run that found nothing must fail, not pass quietly. If the scan
	# breaks, an empty set would satisfy every assertion below.
	if phases.size() < 4:
		print("final_table: FAIL — only found %d match phases in world.gd; "
			% phases.size() + "the scan is broken")
		quit(1)
		return

	var problems: Array[String] = []
	for phase: String in phases:
		var shows := MatchUi.final_table_shows(phase)
		if phase == SHOWS_IN and not shows:
			problems.append("%s should show the table and does not" % phase)
		elif phase != SHOWS_IN and shows:
			problems.append("%s leaves the table on screen" % phase)

	# The phase the bug was actually about, named outright so a future
	# reader knows it is covered on purpose and not by luck.
	if not phases.has("IDLE"):
		problems.append("IDLE is not among the phases found — this test is "
			+ "no longer checking the case it was written for")

	# And a phase nobody has invented yet must default to hiding it.
	if MatchUi.final_table_shows("SOMETHING_NEW"):
		problems.append("an unknown phase leaves the table on screen")

	if problems.is_empty():
		print("final_table: PASS — %d phases, only %s shows the table"
			% [phases.size(), SHOWS_IN])
		quit(0)
	else:
		print("final_table: FAIL")
		for p: String in problems:
			print("  " + p)
		quit(1)

## Every phase world.gd ever puts the match into — read from the source,
## so this cannot drift out of date the way a copied list would.
func _phases_in_world() -> Array[String]:
	var text := FileAccess.get_file_as_string("res://src/world.gd")
	var found := {}
	var regex := RegEx.new()
	# match_phase = "X"   and   cl_match.rpc("X", ...)
	regex.compile('(?:match_phase\\s*=\\s*|cl_match\\.rpc\\()"([A-Z_]+)"')
	for m: RegExMatch in regex.search_all(text):
		found[m.get_string(1)] = true
	var out: Array[String] = []
	for phase: String in found:
		out.append(phase)
	out.sort()
	return out
