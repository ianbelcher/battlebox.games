extends SceneTree
## THE WORLD MENU BUILDS THE CONTROLS IT IS SUPPOSED TO.
##
## A menu that fails to build is invisible to everything else here: the
## unit tests pass, the server runs, the console is clean, and the page is
## empty or has the wrong buttons on it. Screenshots would catch it, but
## software rendering manages about one frame a second and the menu opens
## on a timer, so in practice they catch the loading screen.
##
## This only asks what was BUILT — counts and labels. What each control
## then means is FlyRule's job, and that is unit tested.
##
##     godot --headless --path game --script res://tests/menu_controls.gd

func _initialize() -> void:
	var menu: Node = load("res://src/world_menu.gd").new()
	get_root().add_child(menu)
	await process_frame
	await process_frame
	var bad: PackedStringArray = []

	# Three sizes, doubling. Seven near-identical numbers were a row you
	# could not choose from.
	var sizes: Array = menu.get("_size_btns").keys()
	sizes.sort()
	if sizes != [50, 100, 200, 400, 800]:
		bad.append("sizes are %s, expected [50, 100, 200, 400, 800]" % str(sizes))

	# Four answers for who can fly, and NO world-level on/off switch —
	# flying is a property of a player, and having it in both places is
	# what made the map say "no flying" while three people were airborne.
	var answers: Array = menu.get("_fly_answer_btns").keys()
	answers.sort()
	var want: Array = FlyRule.ANSWERS.duplicate()
	want.sort()
	if answers != want:
		bad.append("fly answers are %s, expected %s" % [str(answers), str(want)])
	if menu.get("_fly_btns") != null:
		bad.append("the old world-level flying switch is still here")

	# Capturing belongs to capture the flag alone; last flag standing has
	# no target to reach and showed "First to 3" regardless.
	for group: String in ["_capture_only", "_holdout_only"]:
		var nodes: Variant = menu.get(group)
		if nodes == null or (nodes as Array).is_empty():
			bad.append("%s is empty — the mode-specific card was not built" % group)

	# Can you be picked up at all — a question for every fight mode, not
	# just the flag ones.
	var back: Array = menu.get("_norevive_btns").keys()
	back.sort()
	if back != [0, 1]:
		bad.append("revive on/off buttons are %s, expected [0, 1]" % str(back))

	for line: String in bad:
		print("  FAIL  %s" % line)
	if bad.is_empty():
		print("menu_controls: PASS — %d sizes, %d fly answers, "
			% [sizes.size(), answers.size()]
			+ "capture and last-flag cards built separately, "
			+ "reviving can be switched off")
		quit(0)
	else:
		print("menu_controls: FAILED")
		quit(1)
