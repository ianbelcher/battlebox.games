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

	# WHAT A GAME IS, IS NOT CHANGED FROM INSIDE IT. The mode row, the map
	# row and the world size all lived in here, and every one of them
	# ended the round in progress — the map and the size by rebuilding the
	# world under whoever was standing on it. They are asked on the front
	# page now, before the world exists, and this is what stops them
	# creeping back: they are not "hidden", they are gone.
	for banned: String in ["_mode_btns", "_size_btns", "_map_row", "_saved_row",
			"_fly_answer_btns", "_revive_btns", "_drop_btns", "_target_btns",
			"_length_btns", "_hold_len_btns"]:
		if menu.get(banned) != null:
			bad.append("%s is back — how the game is played is decided "
				% banned + "before it starts, not from inside it")
	# ...and what replaced them: a line that says what this game IS.
	if menu.get("_this_game") == null:
		bad.append("nothing in the menu says what game this is")

	# WHAT IS LEFT IN HERE. Not settings: the score, the code that gets a
	# friend in, and the way out to a different game.
	for wanted: String in ["_this_game", "_score_rows"]:
		if menu.get(wanted) == null:
			bad.append("%s is missing — the menu has nothing to say about "
				% wanted + "the game it is open in front of")

	for line: String in bad:
		print("  FAIL  %s" % line)
	if bad.is_empty():
		print("menu_controls: PASS — nothing in here changes how the game "
			+ "is played; the score and what this game is are both built")
		quit(0)
	else:
		print("menu_controls: FAILED")
		quit(1)
