class_name FinalScores
extends RefCounted
## The card that goes up when a round ends: who won, the team table, and
## every player's knockouts and captures.
##
## It is BUILT each time rather than kept and refilled. A round ends a few
## times an hour at most, the table's shape depends on the mode that just
## finished, and a panel that is rebuilt cannot be showing last round's
## numbers because somebody forgot to clear a row.
##
## Held open for a fixed moment before it can be dismissed — a child who
## is already pressing something must not skip past the result of a game
## they just spent ten minutes on without seeing it.

## The shell that owns the screen this is drawn onto.
var shell: Main = null

func _init(owner: Main) -> void:
	shell = owner

## HOW LONG THE RESULT STAYS PUT before anything can dismiss it. A
## controller press lands the instant a round ends — somebody is always
## holding a trigger — so without this the scoreboard would flash up and
## vanish before anyone had read a line of it.
const FINAL_HOLD := 5.0

## THE FINAL SCORE, on screen, the moment a battle ends.
##
## The end of a match only ever announced who won. The table itself was
## tucked away under ` → Scores, which nobody is going to open in
## the ten seconds between battles — so as far as anyone playing was
## concerned there were no player stats at all. It now comes up by
## itself, and goes away when the next battle starts.
## The card itself, or null when no round has just ended.
var panel: PanelContainer = null
var _final_shown_ms := 0

func show(winner: int) -> void:
	hide_now()
	_final_shown_ms = Time.get_ticks_msec()
	var world: Node = Game.world
	if world == null:
		return
	var sc := UiTheme.scale_for(shell.get_viewport_rect().size)
	panel = PanelContainer.new()
	panel.theme = UiTheme.build(sc)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(sc))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -UiTheme.px(430, sc)
	panel.offset_right = UiTheme.px(430, sc)
	panel.offset_top = -UiTheme.px(250, sc)
	panel.offset_bottom = UiTheme.px(250, sc)
	shell._game_screen.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.px(12, sc))
	panel.add_child(box)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_TITLE, sc))
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	if winner >= 0 and winner < world.client_team_names.size():
		var won := int(world.team_wins.get(winner, 0))
		title.text = "🏆  %s WINS" % str(world.client_team_names[winner]).to_upper()
		if won > 1:
			title.text += "  ·  %d ON THIS MAP" % won
		title.add_theme_color_override("font_color",
			WorldNode.TEAM_COLORS[winner] if winner < WorldNode.TEAM_COLORS.size()
			else UiTheme.ACCENT)
	else:
		title.text = "NO WINNER THIS TIME"
	box.add_child(title)
	box.add_child(HSeparator.new())

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", UiTheme.px(46, sc))
	split.alignment = BoxContainer.ALIGNMENT_CENTER
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	split.add_child(_final_teams(world, sc))
	split.add_child(_final_players(world, sc))

	var hint := Label.new()
	hint.text = "The full table is under G → Scores"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_NOTE, sc))
	hint.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	box.add_child(hint)

	# A way out that is always on the panel. Every other route off this
	# screen depends on something else happening — the next battle
	# starting, somebody resetting the map — and when none of that comes,
	# there was nothing at all to press.
	#
	# It takes focus so Enter and a gamepad's Ⓐ both work through Godot's
	# ui_accept, which is what the kids on pads will reach for. Space and
	# Escape are handled in _unhandled_input.
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(UiTheme.px(220, sc), UiTheme.px(46, sc))
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void:
		Sfx.play("tick", -8.0)
		hide_now())
	box.add_child(close)
	close.grab_focus.call_deferred()
	# The mouse is held captive while you play, so nothing on this panel
	# could be clicked. Hand the cursor back for as long as it is up.
	shell._update_cursor_release()
func _final_teams(world: Node, sc: float) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wrap.add_theme_constant_override("separation", UiTheme.px(6, sc))
	# THIS GAME first, the running tally second. "Red wins, 2 on this map"
	# tells you who won and how the series stands, and says nothing at all
	# about the round everybody just played — which is the bit they want to
	# argue about. In capture the flag that round has a real scoreline, so
	# show it: taken, lost, and the net each team finished on.
	if str(world.client_mode) == "ctf":
		wrap.add_child(_final_head("THIS GAME", sc))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", UiTheme.px(10, sc))
		wrap.add_child(head)
		for col in [["", 120], ["TOOK", 50], ["LOST", 50], ["SCORE", 50]]:
			var h := Label.new()
			h.text = str(col[0])
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT \
				if str(col[0]) != "" else HORIZONTAL_ALIGNMENT_LEFT
			h.custom_minimum_size = Vector2(UiTheme.px(int(col[1]), sc), 0)
			h.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_NOTE, sc))
			h.add_theme_color_override("font_color", UiTheme.INK_FAINT)
			head.add_child(h)
		var ctf_teams: Array = []
		for t in int(world.team_count):
			ctf_teams.append(t)
		ctf_teams.sort_custom(func(a: int, b: int) -> bool:
			return int(world.ctf_scores.get(a, 0)) > int(world.ctf_scores.get(b, 0)))
		for t: int in ctf_teams:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", UiTheme.px(10, sc))
			wrap.add_child(row)
			var tint: Color = WorldNode.TEAM_COLORS[t] \
				if t < WorldNode.TEAM_COLORS.size() else Color.WHITE
			for cell in [[str(world.client_team_names[t]) \
						if t < world.client_team_names.size() else "Team %d" % (t + 1), 120],
					[str(int(world.ctf_caps.get(t, 0))), 50],
					[str(int(world.ctf_lost.get(t, 0))), 50],
					[str(int(world.ctf_scores.get(t, 0))), 50]]:
				var lbl := Label.new()
				lbl.text = str(cell[0])
				lbl.custom_minimum_size = Vector2(UiTheme.px(int(cell[1]), sc), 0)
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT \
					if int(cell[1]) == 50 else HORIZONTAL_ALIGNMENT_LEFT
				lbl.add_theme_font_size_override("font_size",
					UiTheme.px(UiTheme.T_BODY, sc))
				lbl.add_theme_color_override("font_color", tint)
				row.add_child(lbl)
		wrap.add_child(HSeparator.new())
	wrap.add_child(_final_head("GAMES WON", sc))
	var teams: Array = []
	for t in int(world.team_count):
		teams.append(t)
	teams.sort_custom(func(a: int, b: int) -> bool:
		return int(world.team_wins.get(a, 0)) > int(world.team_wins.get(b, 0)))
	for t: int in teams:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTheme.px(10, sc))
		wrap.add_child(row)
		var name_label := Label.new()
		name_label.text = str(world.client_team_names[t]) 			if t < world.client_team_names.size() else str(t + 1)
		name_label.custom_minimum_size = Vector2(UiTheme.px(120, sc), 0)
		name_label.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_LABEL, sc))
		if t < WorldNode.TEAM_COLORS.size():
			name_label.add_theme_color_override("font_color", WorldNode.TEAM_COLORS[t])
		row.add_child(name_label)
		var wins := Label.new()
		wins.text = str(int(world.team_wins.get(t, 0)))
		wins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		wins.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_BODY, sc))
		wins.add_theme_color_override("font_color", UiTheme.ACCENT)
		wins.custom_minimum_size = Vector2(UiTheme.px(50, sc), 0)
		row.add_child(wins)
	return wrap
func _final_players(world: Node, sc: float) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wrap.add_theme_constant_override("separation", UiTheme.px(6, sc))
	wrap.add_child(_final_head("KNOCKOUTS", sc))
	var names: Array = world.player_frags.keys()
	if names.is_empty():
		var none := Label.new()
		none.text = "Nobody knocked anybody out."
		none.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_LABEL, sc))
		none.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		wrap.add_child(none)
		return wrap
	# This game first, then the running total — the game just played is
	# what everyone wants to see the second it finishes.
	names.sort_custom(func(a: String, b: String) -> bool:
		var la := int(world.player_frags[a].get("last", 0))
		var lb := int(world.player_frags[b].get("last", 0))
		if la != lb:
			return la > lb
		return int(world.player_frags[a].get("total", 0)) 			> int(world.player_frags[b].get("total", 0)))
	# Three columns hugged left, the team carried by the NAME'S COLOUR.
	# Four full-width columns left a chasm between the names and the
	# numbers, and a "Team" column repeating what the colour already says.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UiTheme.px(20, sc))
	grid.add_theme_constant_override("v_separation", UiTheme.px(5, sc))
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wrap.add_child(grid)
	for head_text in ["Player", "This game", "Total"]:
		var head := Label.new()
		head.text = str(head_text)
		head.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_NOTE, sc))
		head.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		if head_text != "Player":
			head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(head)
	var shown := 0
	for who: String in names:
		if shown >= 10:
			break
		shown += 1
		var row: Dictionary = world.player_frags[who]
		var team := int(row.get("team", -1))
		var tint: Color = WorldNode.TEAM_COLORS[team] \
			if team >= 0 and team < WorldNode.TEAM_COLORS.size() else UiTheme.INK
		for spec in [[who, HORIZONTAL_ALIGNMENT_LEFT, tint],
				[str(int(row.get("last", 0))), HORIZONTAL_ALIGNMENT_RIGHT, tint],
				[str(int(row.get("total", 0))), HORIZONTAL_ALIGNMENT_RIGHT,
					UiTheme.INK_FAINT]]:
			var cell := Label.new()
			cell.text = str(spec[0])
			cell.horizontal_alignment = spec[1]
			cell.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_LABEL, sc))
			cell.add_theme_color_override("font_color", spec[2])
			grid.add_child(cell)
	return wrap
func _final_head(text: String, sc: float) -> Label:
	var head := Label.new()
	head.text = text
	head.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_HEADING, sc))
	head.add_theme_color_override("font_color", UiTheme.INK_DIM)
	return head
func dismissable() -> bool:
	return Time.get_ticks_msec() - _final_shown_ms > int(FINAL_HOLD * 1000.0)
## ANY BUTTON ON ANY PAD closes it, once it has been up long enough.
##
## It was Space, Enter or Escape, which on a controller is nothing at all:
## the panel's Close button holds focus so `ui_accept` reaches it, but only
## while focus has not moved, and a round ending with four kids on pads
## left a scoreboard nobody could get rid of. Polled rather than
## event-driven because Godot only raises joypad button events for pads it
## has actions bound for, and this needs to answer to ALL of them.
func poll_dismiss() -> void:
	if not is_instance_valid(panel) or not dismissable():
		return
	for pad in Input.get_connected_joypads():
		for button in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
				JOY_BUTTON_START, JOY_BUTTON_BACK]:
			if Input.is_joy_button_pressed(pad, button):
				hide_now()
				return
func hide_now() -> void:
	if is_instance_valid(panel):
		panel.queue_free()
	panel = null
	shell._update_cursor_release()
