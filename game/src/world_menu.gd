class_name WorldMenu
extends Control
## The WORLD menu (G): the three things worth knowing while a game is
## running, and nothing that changes it.
##
##   Game     what this game IS (read only), how the round is going, the
##            code that gets a friend in, and the way out to another game
##   Players  who is here, their names and teams, and computer players
##   Audio    talking to each other, and how loud everything is
##   Video    how the world is drawn, and what this machine is running
##   Credits
##
## IT USED TO BE A SETTINGS PAGE and that is the thing that changed. The
## mode, the map, the world's size, the round length, the capture target,
## how you get back up, who can fly — all of it was in here, reachable
## mid-round by anybody who opened a menu. The mode and the map threw the
## round away and rebuilt the world under whoever was standing on it; the
## rest changed the rules out from under people halfway through. One
## person idly reading a menu, everyone else's game gone.
##
## Every one of those is asked on the front page now, before the world
## exists, which is the only moment any of them is free to answer. See
## game_setup.gd. Nothing in here changes how the game is played, and
## tests/menu_controls.gd fails if any of it comes back.
##
## KEYBOARD AND MOUSE, both:
##   mouse     click anything
##   keyboard  Enter presses, G or Escape closes
##   pads      cannot reach it: _input() swallows joypad EVENTS while open.
##             Players are driven by POLLING, so the kids keep running
##             around on their controllers while a grown-up sorts things.
##
## LOOK: every colour, radius, padding and font size comes from UiTheme —
## the theme is built once per scale and hung on the panel, so this file
## says WHAT each control is and never how to paint it.
##
## TWO RULES, both learned the hard way:
##
## 1. NEVER rebuild on a timer. This menu used to rebuild every row every
##    frame, which destroyed the text box you were typing in and the
##    button you were half way through clicking. Rows are rebuilt only
##    when their data actually changed — see _sig_of_roster().
## 2. NEVER read `size` during _ready(). The control has no size yet, so
##    every font baked itself at the minimum scale and never grew: tiny
##    text beside theme-scaled buttons, and sliders one hairline high
##    stretched across a 4K screen. Scale comes from the VIEWPORT and is
##    re-applied on every resize — see _apply_scale().

## SOMEWHERE ELSE. Emitted when somebody asks to leave this game and go
## back to the list; main.gd owns the socket and does the leaving. See
## _build_leaving_card for why this exists at all.
signal leave_requested

var world: Node = null

var _panel: PanelContainer
var _tabs: TabContainer
var _players_box: VBoxContainer
var _this_game: Label
var _add_bot_btn: Button
var _voice_btn: Button
var _voice_mute_btn: Button
var _voice_note: Label

## Everything that must resize with the window, with the size it was
## designed at. Registered at build time, re-applied whenever the window
## changes — never baked in once.
var _fonts: Array = []   # [[Control, base_px], ...]
var _mins: Array = []    # [[Control, base_w, base_h], ...]
var _cards: Array = []   # PanelContainers painted with UiTheme.card_box
var _pills: Array = []   # PanelContainers painted with UiTheme.hint_box
var _pads: Array = []    # [[MarginContainer, base_margin], ...]
var _repaint: Array = [] # Callables that redraw a control at the new scale
var _last_scale := 0.0

## What the roster was last built from. Rebuilt only when it changes.
var _roster_sig := ""

# ------------------------------------------------------------------
# Scale
# ------------------------------------------------------------------

## Sized off the real screen, never off this control's not-yet-known size.
## A 4K TV gets big text, a small window gets small text, both readable.
func _scale() -> float:
	return UiTheme.scale_for(get_viewport_rect().size)

func _s(n: int) -> int:
	return UiTheme.px(n, _scale())

## Registers a font so it grows with the window.
func _font(c: Control, base: int) -> Control:
	_fonts.append([c, base])
	c.add_theme_font_size_override("font_size", UiTheme.px(base, _scale()))
	return c

## Registers a minimum size, in design units.
func _min(c: Control, w: int, h: int) -> Control:
	_mins.append([c, w, h])
	c.custom_minimum_size = Vector2(w * _scale(), h * _scale())
	return c

## Walks a ready-made hint row and registers its parts for rescaling.
func _adopt_hints(row: Control) -> Control:
	for node in row.find_children("*", "", true, false):
		if node is PanelContainer:
			_pills.append(node)
		elif node is Label:
			_fonts.append([node, UiTheme.T_HINT])
	return row

func _apply_scale() -> void:
	var sc := _scale()
	if is_equal_approx(sc, _last_scale):
		return
	_last_scale = sc
	if _panel != null:
		_panel.theme = UiTheme.build(sc)
		_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(sc))
		# A dialog, not a wall: capped in design units so a 4K TV gets a
		# bigger menu, not a menu stretched to the width of the room.
		var vp := get_viewport_rect().size
		var w := minf(vp.x * 0.90, 1120.0 * sc)
		var h := minf(vp.y * 0.90, 940.0 * sc)
		# Grow from the MIDDLE. Godot's default is to grow right and down,
		# so the moment a tab's content needed more width than the panel
		# had — which capture the flag's settings did — the whole menu slid
		# off the right-hand edge of the screen instead of staying centred.
		_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		_panel.anchor_left = 0.5
		_panel.anchor_right = 0.5
		_panel.anchor_top = 0.5
		_panel.anchor_bottom = 0.5
		_panel.offset_left = -w * 0.5
		_panel.offset_right = w * 0.5
		_panel.offset_top = -h * 0.5
		_panel.offset_bottom = h * 0.5
	for entry: Array in _fonts:
		var c: Control = entry[0]
		if is_instance_valid(c):
			c.add_theme_font_size_override("font_size", UiTheme.px(int(entry[1]), sc))
	for entry: Array in _mins:
		var c2: Control = entry[0]
		if is_instance_valid(c2):
			c2.custom_minimum_size = Vector2(int(entry[1]) * sc, int(entry[2]) * sc)
	for card: PanelContainer in _cards:
		if is_instance_valid(card):
			card.add_theme_stylebox_override("panel", UiTheme.card_box(sc))
	for pill: PanelContainer in _pills:
		if is_instance_valid(pill):
			pill.add_theme_stylebox_override("panel", UiTheme.hint_box(sc))
	for entry: Array in _pads:
		var pad: MarginContainer = entry[0]
		if is_instance_valid(pad):
			for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
				pad.add_theme_constant_override(side, UiTheme.px(int(entry[1]), sc))
	for job: Callable in _repaint:
		job.call()
	# Rows carrying hand-painted styleboxes (the team swatches) are rebuilt
	# rather than patched — this runs on window resize only, never on a
	# timer, so it does not break the "no rebuild" rule.
	_roster_sig = ""

# ------------------------------------------------------------------
# Build
# ------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = UiTheme.SCRIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.theme = UiTheme.build(_scale())
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(_scale()))
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", _s(14))
	_panel.add_child(outer)
	outer.add_child(_build_header())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Focusable: that is how the KEYBOARD drives this menu. Pads are kept
	# out in _input(), not by making everything unfocusable (which locked
	# the keyboard out along with them).
	_tabs.focus_mode = Control.FOCUS_ALL
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	outer.add_child(_tabs)
	# GAME first, because the mode decides what the rest of this menu even
	# means — and soon which tabs exist at all. Then the map it is played
	# on, then who is playing.
	#
	# No Scores tab here: this menu freezes everyone at the table while it
	# is open, so it is the wrong place to browse a scoreboard. Scores live
	# in each player's own menu, where they only appear in a mode that HAS
	# them (see PlayerHud._page_visible).
	#
	# No Help tab either — the controls are on every player's own menu,
	# and a second copy behind a modal that stops the game was never where
	# anyone looked.
	_build_game_tab()
	_build_players_tab()
	_build_audio_tab()
	_build_video_tab()
	_build_credits_tab()

	# WHAT THE KEY ACTUALLY IS. This said "Esc Close", which is wrong —
	# Escape does close it, but the key that OPENS it is the one worth
	# knowing, and that is G. "Tab Move" is gone: nobody tabs through a
	# menu they can click, and it was the widest thing on the row.
	outer.add_child(_adopt_hints(UiTheme.hint_row(
		["G", "Close", "↵", "Choose"], _scale())))
	Game.roster_changed.connect(_mark_dirty)
	get_viewport().size_changed.connect(_apply_scale)
	_apply_scale.call_deferred()

## Title block: who this menu belongs to on the left, how to leave on the
## right. Every screen in the game opens with this same shape.
func _build_header() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _s(12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _s(14))
	box.add_child(row)

	var mark := Label.new()
	mark.text = "🌍"
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_font(mark, UiTheme.T_TITLE))

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(titles)
	var title := Label.new()
	title.text = "WORLD"
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	titles.add_child(_font(title, UiTheme.T_TITLE))
	var sub := Label.new()
	# NOT "settings" any more. Everything this menu could set is decided on
	# the front page before the world exists; what is left is the score,
	# the way in for a friend, and the way out to another game.
	sub.text = "How this game is going, and who else can join"
	sub.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	titles.add_child(_font(sub, UiTheme.T_NOTE))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_adopt_hints(UiTheme.hint_row(["G", "Close"], _scale())))

	var rule := HSeparator.new()
	box.add_child(rule)
	return box

func _mark_dirty() -> void:
	_roster_sig = ""

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Controllers are locked out; their PLAYERS are not (player input is
	# polled, never event-driven), so the kids keep playing regardless.
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		return
	# A focused text box would otherwise eat Escape and trap you in here.
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit:
			focused.release_focus()

func open() -> void:
	visible = true
	_last_scale = 0.0
	_apply_scale()
	_refresh(true)
	_tabs.get_tab_bar().grab_focus.call_deferred()

func close() -> void:
	visible = false
	# Don't leave the highlight parked on a hidden button — the next Enter
	# in the game world would press it.
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

# ------------------------------------------------------------------
# Widgets
# ------------------------------------------------------------------

## A tab page: scrolls vertically, with breathing room around the content
## so nothing ever touches the panel edge.
func _tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, _s(16))
	_pads.append([pad, 16])
	scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", _s(14))
	pad.add_child(box)
	return box

## A section title: small, quiet, upper-case, with a hairline running out
## to the right edge. Reads as structure rather than as another button.
func _heading(parent: Control, text: String, note := "") -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", _s(4))
	parent.add_child(group)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _s(12))
	group.add_child(row)
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_color_override("font_color", UiTheme.INK_DIM)
	row.add_child(_font(label, UiTheme.T_HEADING))
	var rule := HSeparator.new()
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rule)
	if not note.is_empty():
		var sub := Label.new()
		sub.text = note
		sub.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		group.add_child(_font(sub, UiTheme.T_NOTE))
	return group

## A grouped block of controls on its own raised surface.
func _card(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(_scale()))
	_cards.append(card)
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _s(10))
	card.add_child(box)
	return box

## A section = heading + its own card. The pairing every tab uses.
func _section(parent: Control, text: String, note := "") -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", _s(8))
	parent.add_child(group)
	_heading(group, text, note)
	return _card(group)

func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _s(8))
	parent.add_child(row)
	return row

func _button(text: String, on_press: Callable, base := UiTheme.T_BODY) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.text = text
	btn.clip_text = true
	_font(btn, base)
	_min(btn, 0, 44)
	btn.pressed.connect(func() -> void:
		on_press.call()
		Sfx.play("tick", -8.0))
	return btn

## One choice out of several: every button in the row is the same width,
## so the row reads as a single segmented control rather than as a ragged
## line of unrelated buttons.
func _choice(row: HBoxContainer, text: String, on_press: Callable,
		base := UiTheme.T_BODY) -> Button:
	var btn := _button(text, on_press, base)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(btn)
	return btn

## Paints the chosen entry gold. Cheap to call every refresh: it does
## nothing unless the state (or the scale) actually changed.
func _mark(btn: Button, on: bool) -> void:
	if not is_instance_valid(btn):
		return
	var want := "%d@%f" % [1 if on else 0, _last_scale]
	if str(btn.get_meta("mark", "")) == want:
		return
	btn.set_meta("mark", want)
	if on:
		var sel := UiTheme.selected_box(_last_scale)
		for state in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(state, sel)
		btn.add_theme_color_override("font_color", UiTheme.ON_ACCENT)
		btn.add_theme_color_override("font_hover_color", UiTheme.ON_ACCENT)
	else:
		for state in ["normal", "hover", "pressed"]:
			btn.remove_theme_stylebox_override(state)
		btn.remove_theme_color_override("font_color")
		btn.remove_theme_color_override("font_hover_color")

# ------------------------------------------------------------------
# Game — what kind of game this is
# ------------------------------------------------------------------

## WHAT KIND OF GAME THIS IS, IS NOT CHANGED FROM INSIDE IT.
##
## There was a row of mode buttons at the top of this tab and a Map tab
## beside it, and pressing anything in either ended the round everybody
## was playing — and, for the map or the size, rebuilt the world under
## their feet while they were standing on it. One person idly reading the
## menu, everyone else's game gone.
##
## A game is what it was made as. The front page asks all of it before
## the world exists (see game_setup.gd), which is the only moment any of
## those answers is free — and going to play a different one is the card
## at the foot of this tab.
##
## What is left here is everything that can be changed WITHOUT throwing
## the round away: how you get back up, what happens when you are knocked
## out, what it takes to win, and how long a round runs.
## THE ONLY TAB THAT IS ABOUT THIS GAME, and it does not change it.
##
## It used to be a settings page: the mode, the map, the world's size, how
## long a round runs, what it takes to win, how you get back up, who can
## fly. Every one of those decides how the game is PLAYED, and every one
## of them was reachable, mid-round, by anybody who opened a menu — the
## mode and the map by throwing the round away and rebuilding the world
## under whoever was standing on it, the rest by changing the rules out
## from under people halfway through.
##
## They are all asked on the front page now, before the world exists,
## which is the only moment any of them is free to answer (see
## game_setup.gd). What is left in here is the three things you actually
## want from a menu while a game is running:
##
##   how it is going     the score
##   who else            the code and the link that get a friend in
##   somewhere else      leaving, to go and play a different game
func _build_game_tab() -> void:
	var box := _tab("Game")
	_build_this_game_card(box)
	_build_score_card(box)
	_build_invite_card(box)
	_build_leaving_card(box)

## WHAT THIS GAME IS, as a sentence rather than as a row of buttons.
##
## The mode and the map are still worth KNOWING from in here — somebody
## who joined by a link has no idea what they walked into — they are just
## not worth being able to change.
func _build_this_game_card(box: Control) -> void:
	var card := _section(box, "This game")
	_this_game = Label.new()
	_this_game.add_theme_color_override("font_color", UiTheme.INK)
	_this_game.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_font(_this_game, UiTheme.T_BODY))
	var note := Label.new()
	note.text = "Chosen when the game was made."
	note.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	card.add_child(_font(note, UiTheme.T_NOTE))

func _refresh_this_game() -> void:
	if _this_game == null or world == null:
		return
	var mode := str(world.client_mode)
	var parts: Array = [GameSetup.mode_label(mode)]
	var map_key := str(world.client_world)
	if not map_key.is_empty():
		parts.append(GameSetup.map_label(map_key))
	if world.client_size > 0:
		parts.append("%d across" % int(world.client_size))
	_this_game.text = " · ".join(parts)

## THE WAY OUT, and it is at the foot of the tab that changes the game
## on purpose.
##
## Everything above this card changes the game you are IN: a different
## mode ends the round being played, a different map resets the world
## under whoever is standing on it. That is a lot of consequence for
## "actually, let us play capture the flag instead", and it is the reason
## the front page now sets a game up BEFORE it exists.
##
## But the front page was a one-way door: once you were in a game the
## only way to a different one was to reload the page, which on a tablet
## handed to a five-year-old is not a route that exists. So this is the
## other half of that change — the settings above are still here for the
## game you are in, and this is how you go and play a different one.
##
## NOTHING IS LOST BY PRESSING IT. The room keeps running with whoever
## else is in it, and a room you created is still reachable by its code
## for as long as somebody is there.
func _build_leaving_card(box: Control) -> void:
	var card := _section(box, "Playing something else",
		"The game carries on without you, and you can come back to it.")
	var leave := _button("Leave and pick another game", func() -> void:
		close()
		leave_requested.emit())
	_min(leave, 300, 46)
	card.add_child(leave)

## HOW THE ROUND IS GOING — its own tab, next to Players.
##
## It was a card at the top of the Game tab, above "How are we playing?",
## which is a settings page: you went to the game SETTINGS to read the
## SCORE, and the first thing above the mode buttons was a table. Wrong
## place, and wrong thing to put first.
##
## The scores otherwise live in exactly two places — down the side during
## play, and on the end card — so opening the menu mid-round to check them
## showed nothing, and once the round ended the only way back to the
## number was to play another. In last flag standing that is ten minutes
## to answer "how are we doing".
##
## COLUMNS NEED HEADINGS. The first version had none, so a row read
## "Blue  holding  3 took  3  1/1 up" and there was no way to tell what
## any of those numbers were. Same table as the end card, so the two
## cannot disagree.
var _score_rows: VBoxContainer
var _score_sig := ""
var _score_empty: Label

func _build_score_card(box: Control) -> void:
	var card := _section(box, "How it is going")
	_score_empty = Label.new()
	_score_empty.text = "No round is running yet."
	_score_empty.add_theme_color_override("font_color", UiTheme.INK_DIM)
	card.add_child(_font(_score_empty, UiTheme.T_LABEL))
	_score_rows = VBoxContainer.new()
	_score_rows.add_theme_constant_override("separation", _s(2))
	card.add_child(_score_rows)

## One row of the table. `head` draws it as a heading rather than a team.
func _score_row(cells: Array, tint: Color, head := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _s(10))
	_score_rows.add_child(row)
	for cell: Array in cells:
		var lbl := Label.new()
		lbl.text = str(cell[0])
		lbl.custom_minimum_size = Vector2(_s(int(cell[1])), 0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if int(cell[1]) > 100 \
			else HORIZONTAL_ALIGNMENT_RIGHT
		lbl.add_theme_color_override("font_color", UiTheme.INK_FAINT if head else tint)
		_font(lbl, UiTheme.T_NOTE if head else UiTheme.T_LABEL)
		row.add_child(lbl)

func _refresh_live_score() -> void:
	if _score_rows == null or world == null:
		return
	var running: bool = world.match_phase != "IDLE" and world.client_mode != "creative"
	_score_empty.visible = not running
	if not running:
		if _score_sig != "":
			_score_sig = ""
			for stale in _score_rows.get_children():
				stale.queue_free()
		return
	var flags: bool = world.flag_mode()
	var sig := "%s|%s|%s|%s|%d" % [world.match_phase, str(world.ctf_scores),
		str(world.ctf_caps), str(world.alive_ids), int(world.team_count)]
	if sig == _score_sig:
		return
	_score_sig = sig
	for stale in _score_rows.get_children():
		stale.queue_free()
	var order: Array = []
	for team_i in int(world.team_count):
		order.append(team_i)
	if flags:
		order.sort_custom(func(a: int, b: int) -> bool:
			return int(world.ctf_scores.get(a, 0)) > int(world.ctf_scores.get(b, 0)))
	var head: Array = [["TEAM", 130], ["STILL UP", 80]]
	if flags:
		head.append(["FLAG", 80])
		head.append(["TOOK", 60])
		head.append(["LOST", 60])
		# Last flag standing is settled once, at the whistle — a running
		# score would be a number that means nothing until then.
		if world.client_mode != "holdout":
			head.append(["SCORE", 60])
	_score_row(head, UiTheme.INK_FAINT, true)
	for team_v: Variant in order:
		var t := int(team_v)
		var standing := 0
		var total := 0
		for rid: String in Game.roster.keys():
			if int(Game.roster[rid].get("team", -1)) != t:
				continue
			total += 1
			if world.alive_ids.has(rid) and not world.client_downed.has(rid):
				standing += 1
		if total == 0:
			continue
		var cells: Array = [[_team_name(t), 130], ["%d of %d" % [standing, total], 80]]
		if flags:
			cells.append(["gone" if _flag_gone(t) else "up", 80])
			cells.append([str(int(world.ctf_caps.get(t, 0))), 60])
			cells.append([str(int(world.ctf_lost.get(t, 0))), 60])
			if world.client_mode != "holdout":
				cells.append([str(int(world.ctf_scores.get(t, 0))), 60])
		_score_row(cells, WorldNode.TEAM_COLORS[t % WorldNode.TEAM_COLORS.size()] \
			if standing > 0 else Color(0.55, 0.55, 0.6))


## Has this team's flag been taken for good? Client-side, off the flag
## list the server broadcasts.
func _flag_gone(team: int) -> bool:
	for entry: Variant in world.flags:
		var f: Array = entry
		if int(f[0]) == team:
			return f.size() > 3 and bool(f[3])
	return false

# ------------------------------------------------------------------
# Players
# ------------------------------------------------------------------

func _build_players_tab() -> void:
	var box := _tab("Players")

	var manage_card := _section(box, "Teams and computer players")
	# Two per row, not four: at four across, "Add a computer player" was
	# wider than its column and lost its last word. Plain ASCII +/− on
	# purpose too — the full-width ＋／－ glyphs are missing from the
	# bundled font and rendered as tofu boxes.
	var team_row := _row(manage_card)
	var bot_row := _row(manage_card)
	var fill_row := _row(manage_card)
	for spec in [["+  Add a team", "add_team", 0],
			["−  Remove a team", "remove_team", 0],
			["+  Add a computer player", "add_bot", 1],
			["−  Remove a computer player", "remove_bot", 1],
			["🤖  Fill up to %d" % Game.MAX_PLAYERS, "fill_bots", 2]]:
		var manage: HBoxContainer = team_row
		if int(spec[2]) == 1:
			manage = bot_row
		elif int(spec[2]) == 2:
			manage = fill_row
		var action := str(spec[1])
		var press := func() -> void:
			if Game.world == null:
				return
			match action:
				"add_team":
					Game.world.sv_add_team.rpc_id(1)
				"remove_team":
					Game.world.sv_remove_team.rpc_id(1, -1)
				"add_bot":
					Game.world.sv_add_bot.rpc_id(1)
				"remove_bot":
					Game.world.sv_remove_bot.rpc_id(1, "")
				"fill_bots":
					Game.world.sv_fill_bots.rpc_id(1)
		var btn := _choice(manage, str(spec[0]), press)
		_min(btn, 150, 50)
		if action == "add_bot":
			_add_bot_btn = btn

	var roster_card := _section(box, "Everyone playing",
		"Click a name to type a new one. Click a colour to change team.")
	# Horizontal scroll is the backstop: the swatches shrink as teams are
	# added, but at 24 teams on a small window they still have to go
	# somewhere. Before this the row simply ran off the right of the panel
	# and out of the window.
	var roster_scroll := ScrollContainer.new()
	roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_card.add_child(roster_scroll)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_box.add_theme_constant_override("separation", _s(6))
	roster_scroll.add_child(_players_box)

## Rows are rebuilt ONLY when this changes — never on a timer. Rebuilding
## every frame destroyed the text box you were typing into.
func _sig_of_roster() -> String:
	var teams: int = world.team_count if world != null else 4
	var ids: Array = Game.roster.keys()
	ids.sort()
	var out := "t%d|" % teams
	for id: String in ids:
		var e: Dictionary = Game.roster[id]
		out += "%s:%s:%s:%s:%s;" % [id, e.get("name", ""), e.get("team", -1),
			e.get("bot", false), e.get("fly", "-")]
	return out

func _refresh_players() -> void:
	if _players_box == null:
		return
	var sig := _sig_of_roster()
	if sig == _roster_sig:
		return
	# Never yank a text box out from under someone mid-rename.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit and _players_box.is_ancestor_of(focused):
		return
	_roster_sig = sig
	for child in _players_box.get_children():
		child.queue_free()
	if _add_bot_btn != null:
		# ONE source of truth for the cap. This was a hardcoded 24 and it
		# is the reason raising MAX_PLAYERS did nothing: every server-side
		# check moved, and the button that does the adding sat there
		# greyed out, so the limit looked like it had not changed at all.
		_add_bot_btn.disabled = Game.roster.size() >= Game.MAX_PLAYERS
	var team_count: int = world.team_count if world != null else 4
	var ids: Array = Game.roster.keys()
	# People first, then computers, each block in name order. Computers are
	# named from the phonetic alphabet, so name order IS the order they
	# were added — Alpha, Bravo, Charlie down the page.
	ids.sort_custom(func(a: String, b: String) -> bool:
		var a_bot: bool = bool(Game.roster[a].get("bot", false))
		var b_bot: bool = bool(Game.roster[b].get("bot", false))
		if a_bot != b_bot:
			return b_bot  # humans first
		return str(Game.roster[a].name) < str(Game.roster[b].name))

	# ONE grid, so the counts along the top sit exactly over the column
	# they are counting. As separate rows they drifted apart the moment a
	# name was a different length.
	var grid := GridContainer.new()
	# name | one cell per team | remove
	grid.columns = team_count + 2
	grid.add_theme_constant_override("h_separation", _s(6))
	grid.add_theme_constant_override("v_separation", _s(6))
	_players_box.add_child(grid)

	var cell_w := int(clampf(480.0 / float(team_count), 30.0, 76.0))
	var counts := _team_counts(team_count)
	grid.add_child(_min(Control.new(), 210, 0))
	for t in team_count:
		grid.add_child(_team_header(t, counts[t], cell_w))
	grid.add_child(Control.new())
	for id_v in ids:
		_add_player_row(grid, str(id_v), team_count, cell_w)

## Whatever the team is actually CALLED — teams can be renamed, and the
## header used to show the hard-coded colour list instead.
func _team_name(t: int) -> String:
	if world != null and t < world.client_team_names.size():
		return str(world.client_team_names[t])
	if t < WorldNode.TEAM_NAMES.size():
		return WorldNode.TEAM_NAMES[t]
	return str(t + 1)

## How many players are sitting on each team right now.
func _team_counts(team_count: int) -> Array:
	var counts: Array[int] = []
	counts.resize(team_count)
	for id: String in Game.roster.keys():
		var team := int(Game.roster[id].get("team", -1))
		if team >= 0 and team < team_count:
			counts[team] += 1
	return counts

## Column header: the team's name over how many are on it. With the count
## up here, the swatches below can be pure colour — which is what lets
## them shrink far enough for 24 teams to fit on screen at all.
func _team_header(t: int, count: int, cell_w: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_min(box, cell_w, 0)
	var name_label := Label.new()
	name_label.text = _team_name(t)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_color_override("font_color", WorldNode.TEAM_COLORS[t])
	# The name shrinks with the column so "Orange" doesn't come out as
	# "Orang" once there are a dozen teams sharing the width.
	box.add_child(_font(name_label,
		int(clampf(cell_w * 0.28, 9.0, float(UiTheme.T_NOTE)))))
	var count_label := Label.new()
	count_label.text = str(count)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_color_override("font_color",
		UiTheme.INK if count > 0 else UiTheme.INK_FAINT)
	box.add_child(_font(count_label, UiTheme.T_BODY))
	return box

func _add_player_row(grid: GridContainer, id: String, team_count: int,
		cell_w: int) -> void:
	var entry: Dictionary = Game.roster[id]
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", _s(8))
	_min(who, 210, 0)
	var tag := Label.new()
	tag.text = "🤖" if bool(entry.get("bot", false)) else "🙂"
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(_font(tag, UiTheme.T_BODY + 4))
	var name_edit := LineEdit.new()
	name_edit.text = str(entry.name)
	name_edit.max_length = 12
	name_edit.focus_mode = Control.FOCUS_ALL
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_min(name_edit, 150, 44)
	_font(name_edit, UiTheme.T_BODY)
	name_edit.text_submitted.connect(func(text: String) -> void:
		Game.sv_rename_any.rpc_id(1, id, text)
		name_edit.release_focus()
		Sfx.play("pop", -6.0))
	name_edit.focus_exited.connect(func() -> void:
		if name_edit.text != str(Game.roster.get(id, {}).get("name", "")):
			Game.sv_rename_any.rpc_id(1, id, name_edit.text))
	who.add_child(name_edit)
	grid.add_child(who)
	var team := int(entry.get("team", -1))
	for t in team_count:
		grid.add_child(_team_cell(id, t, team, cell_w))
	var kick := _button("✕", func() -> void:
		Game.sv_kick_player.rpc_id(1, id)
		Sfx.play("pop", -6.0), UiTheme.T_BODY)
	kick.tooltip_text = "Remove this player"
	kick.add_theme_color_override("font_color", UiTheme.DANGER)
	kick.add_theme_color_override("font_hover_color", Color.WHITE)
	_min(kick, 46, 44)
	grid.add_child(kick)

func _team_cell(id: String, t: int, current: int, cell_w: int) -> Button:
	var entry: Dictionary = Game.roster[id]
	var cell := Button.new()
	cell.focus_mode = Control.FOCUS_ALL
	# Pure colour, no text: the name is in the header above it, and text
	# is what stopped these shrinking when the teams piled up.
	cell.tooltip_text = _team_name(t)
	_min(cell, cell_w, 44)
	# The team a player is ON is fully saturated with a white ring; the
	# others are the same hue knocked right back, so one glance down the
	# column tells you who is where.
	var base: Color = WorldNode.TEAM_COLORS[t]
	var chosen := t == current
	var cell_style := UiTheme.flat(base if chosen else base.darkened(0.62),
		UiTheme.R_CONTROL, _last_scale if _last_scale > 0.0 else _scale(),
		2.0 if chosen else 1.0,
		Color.WHITE if chosen else Color(1, 1, 1, 0.10))
	cell_style.bg_color.a = 1.0
	var hover_style: StyleBoxFlat = cell_style.duplicate()
	hover_style.border_color = Color.WHITE
	cell.add_theme_stylebox_override("normal", cell_style)
	cell.add_theme_stylebox_override("pressed", cell_style)
	cell.add_theme_stylebox_override("hover", hover_style)
	var slot := int(entry.slot)
	var mine: bool = int(entry.peer) == multiplayer.get_unique_id() \
		and Game.local_inputs.has(slot)
	cell.pressed.connect(func() -> void:
		if mine:
			Game.set_local_team(slot, t)
		elif Game.world != null:
			Game.world.sv_set_bot_team.rpc_id(1, id, t)
		Sfx.play("tick", -8.0))
	return cell


## How anybody else gets in here — FIRST in this tab, because it is the
## only question in this menu whose answer you cannot work out by looking
## at the game.
##
## A private room is reachable by exactly one route: somebody says the
## code out loud or sends the link. If you cannot find it again after the
## moment you made it, the room is a dead end — so it lives somewhere
## permanent, and the card on the way in points here.
func _build_invite_card(box: Control) -> void:
	var code := Game.joined_code
	if code.is_empty() or code == Room.HOUSE_CODE:
		# The always-on world. There is nothing to give anybody, because
		# the plain address already lands here — and showing a code would
		# imply this game is private when it is the opposite.
		var open_link := Room.link_for(Game.web_origin(), Room.HOUSE_CODE)
		if open_link.is_empty():
			# Off the web there is no address to hand anybody, so the card
			# would be an empty rounded box under a heading — which is
			# what it was, and it reads as something that failed to load.
			# The heading on its own still says the useful part.
			_heading(box, "Joining in", "Anyone can play — this game is open.")
			return
		var open_card := _section(box, "Joining in",
			"Anyone can play. Send them the address and they land here.")
		open_card.add_child(_font(_copyable(open_link), UiTheme.T_BODY))
		return

	var card := _section(box, "Invite a friend",
		"Give them this and they land straight in this game.")
	var code_label := Label.new()
	code_label.text = code
	code_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	card.add_child(_font(code_label, UiTheme.T_TITLE))
	var link := Room.link_for(Game.web_origin(), code)
	if not link.is_empty():
		var note := Label.new()
		note.text = "Or send this link:"
		note.add_theme_color_override("font_color", UiTheme.INK_DIM)
		card.add_child(_font(note, UiTheme.T_NOTE))
		card.add_child(_font(_copyable(link), UiTheme.T_BODY))

## Text somebody can actually get out of the game. A Label cannot be
## selected, and copying is the only thing anyone wants to do with a link,
## so this is a LineEdit that happens to be read-only.
func _copyable(text: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = text
	field.editable = false
	field.select_all_on_focus = true
	field.add_theme_color_override("font_uneditable_color", UiTheme.INK)
	_min(field, 320, 40)
	return field

# ------------------------------------------------------------------
# Video / Credits
# ------------------------------------------------------------------

func _refresh_voice() -> void:
	if _voice_btn == null or not is_instance_valid(_voice_btn):
		return
	var on: bool = Voice.state == "on"
	_voice_btn.text = "Leave the call" if on else "Turn on voice chat"
	_voice_mute_btn.visible = on
	_voice_mute_btn.text = "Unmute" if Voice.muted else "Mute"
	_mark(_voice_mute_btn, Voice.muted)
	var note := Voice.summary()
	if Voice.state == "denied":
		note += " — allow the microphone in the browser's address bar, "
		note += "then turn it on again."
	_voice_note.text = note

## AUDIO IS ITS OWN TAB. Talking to each other and how loud the game is
## used to live under "Video", which is where they were never going to be
## found: voice chat has nothing to do with video, and neither has volume.
func _build_audio_tab() -> void:
	var box := _tab("Audio")
	# Voice belongs to the MACHINE, like the renderer setting on the Video
	# tab — one microphone per couch, whatever the split screen is doing.
	# See voice.gd for why there are no team channels.
	if Voice.available():
		var talk := _section(box, "Talking to each other",
			"On by default. One call for everyone in the world — the people "
			+ "sharing this screen share its microphone.")
		var talk_row := _row(talk)
		_voice_btn = _choice(talk_row, "Turn on voice chat", func() -> void:
			# set_wanted, not enable/disable: this is the machine saying
			# whether it wants to be in the call at all, and it is
			# remembered, so turning it off stays off next time.
			Voice.set_wanted(Voice.state != "on"))
		_min(_voice_btn, 220, 46)
		_voice_mute_btn = _choice(talk_row, "Mute", func() -> void:
			Voice.toggle_muted())
		_min(_voice_mute_btn, 140, 46)
		_voice_note = Label.new()
		_voice_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_voice_note.add_theme_color_override("font_color", UiTheme.INK_DIM)
		talk.add_child(_font(_voice_note, UiTheme.T_LABEL))
		Voice.state_changed.connect(_refresh_voice)
		_refresh_voice()
	var sound := _section(box, "Volume",
		"How loud the game is, and how loud everyone else is.")
	_stepper(sound, "Game volume", "volume", 0, 100, 10, "%d%%")
	sound.add_child(HSeparator.new())
	_stepper(sound, "Other people", "voice_volume", 0, 100, 10, "%d%%")

func _build_video_tab() -> void:
	var box := _tab("Video")
	var detail := _section(box, "Detail",
		"Turn these down first if the game feels slow.")
	_stepper(detail, "Draw distance", "dist_blocks", 32, 208, 16, "%d blocks")
	detail.add_child(HSeparator.new())
	_stepper(detail, "3D resolution", "render_scale", 10, 100, 5, "%d%%")
	detail.add_child(HSeparator.new())
	_stepper(detail, "Shadow quality", "shadow_quality", 0, 2, 1, "%d")

	var effects := _section(box, "Effects")
	var specs := [["shadows", "Shadows"], ["ssao", "Contact shading (SSAO)"],
		["glow", "Glow"], ["lights", "Dynamic lights"],
		["water_shine", "Shiny water"], ["ao", "Corner shading"],
		["wire", "Wireframe"]]
	for i in specs.size():
		if i > 0:
			effects.add_child(HSeparator.new())
		_toggle(effects, str(specs[i][1]), str(specs[i][0]))

	# Which build this is. Worth knowing everywhere, and the answer to half
	# of the "this feature is missing" reports.
	var system := _section(box, "This machine")
	_setting_row(system, "Game version", "Version " + _local_version(), null)

## label on the left, control on the right — the shape every settings row
## in every game you have ever downloaded uses.
func _setting_row(parent: Control, label: String, note: String,
		control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _s(16))
	parent.add_child(row)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(titles)
	var name_label := Label.new()
	name_label.text = label
	titles.add_child(_font(name_label, UiTheme.T_LABEL))
	if not note.is_empty():
		var sub := Label.new()
		sub.text = note
		sub.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		titles.add_child(_font(sub, UiTheme.T_NOTE))
	# A row with nothing on the right is allowed: some settings are just
	# something to read, like which build this is.
	if control != null:
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(control)
	return row

## An on/off setting. A real pill that says ON or OFF, not a ☐ glyph the
## size of a full stop that nobody could tell apart across a living room.
func _toggle(parent: Control, label: String, key: String) -> void:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	_font(btn, UiTheme.T_NOTE + 1)
	_min(btn, 96, 42)
	var paint := func() -> void:
		var on := bool(Game.video[key])
		btn.text = "ON" if on else "OFF"
		if on:
			var sel := UiTheme.selected_box(_last_scale if _last_scale > 0.0 else _scale())
			for state in ["normal", "hover", "pressed"]:
				btn.add_theme_stylebox_override(state, sel)
			btn.add_theme_color_override("font_color", UiTheme.ON_ACCENT)
			btn.add_theme_color_override("font_hover_color", UiTheme.ON_ACCENT)
		else:
			for state in ["normal", "hover", "pressed"]:
				btn.remove_theme_stylebox_override(state)
			btn.add_theme_color_override("font_color", UiTheme.INK_FAINT)
			btn.remove_theme_color_override("font_hover_color")
	paint.call()
	_repaint.append(paint)
	btn.pressed.connect(func() -> void:
		Game.video[key] = not bool(Game.video[key])
		paint.call()
		Game.video_changed.emit()
		Sfx.play("tick", -10.0))
	_setting_row(parent, label, "", btn)

## A stepper: [ − ]  value  [ + ].
##
## NOT a slider. Godot draws a slider's track and knob from fixed-pixel
## theme textures that ignore custom_minimum_size, so on a 4K screen the
## "Shadow quality 0/1/2" setting rendered as a hairline stretched across
## the whole TV. Buttons scale with everything else, and for a
## three-value setting they're easier for a child to hit anyway.
func _stepper(parent: Control, label: String, key: String, low: int, high: int,
		step: int, fmt: String) -> void:
	var control := HBoxContainer.new()
	control.add_theme_constant_override("separation", _s(4))
	var value_label := Label.new()
	value_label.text = fmt % int(Game.video[key])
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_min(value_label, 150, 42)
	_font(value_label, UiTheme.T_BODY)
	var nudge := func(dir: int) -> void:
		var v := clampi(int(Game.video[key]) + dir * step, low, high)
		Game.video[key] = v
		value_label.text = fmt % v
		Game.video_changed.emit()
	var minus := _button("−", func() -> void: nudge.call(-1), UiTheme.T_TITLE - 8)
	_min(minus, 56, 42)
	control.add_child(minus)
	control.add_child(value_label)
	var plus := _button("+", func() -> void: nudge.call(1), UiTheme.T_TITLE - 8)
	_min(plus, 56, 42)
	control.add_child(plus)
	_setting_row(parent, label, "", control)

func _build_credits_tab() -> void:
	var box := _tab("Credits")
	var intro := Label.new()
	intro.text = "This game stands on other people's work — thank you."
	intro.add_theme_color_override("font_color", UiTheme.INK_DIM)
	box.add_child(_font(intro, UiTheme.T_BODY))
	for group: String in Credits.groups():
		var card := _section(box, group)
		for entry: Dictionary in Credits.in_group(group):
			var line := VBoxContainer.new()
			line.add_theme_constant_override("separation", 0)
			card.add_child(line)
			var head := Label.new()
			head.text = "%s — %s" % [str(entry.name), str(entry.by)]
			head.add_theme_color_override("font_color", UiTheme.INK)
			line.add_child(_font(head, UiTheme.T_LABEL))
			var sub := Label.new()
			sub.text = "%s · %s" % [str(entry.license), str(entry.what)]
			sub.add_theme_color_override("font_color", UiTheme.INK_FAINT)
			sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_child(_font(sub, UiTheme.T_NOTE))
	if not Credits.builds().is_empty():
		var builds_card := _section(box, "Imported builds")
		for entry: Dictionary in Credits.builds():
			var line := Label.new()
			line.text = "%s — built by %s  (%s)" % [str(entry.get("name", "?")),
				str(entry.get("by", "unknown")), str(entry.get("license", "?"))]
			line.add_theme_color_override("font_color", UiTheme.INK_DIM)
			builds_card.add_child(_font(line, UiTheme.T_NOTE + 1))

## Which build this is, from the version stamped into the pack at build
## time. "dev" when running from source.
func _local_version() -> String:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else "dev"

func _refresh(force := false) -> void:
	if not visible:
		return
	if force:
		_roster_sig = ""
	_refresh_players()
	_refresh_live_score()
	if world == null:
		return
	_refresh_this_game()

var _auto_ms := 0
var _tick := 0.0

func _process(delta: float) -> void:
	if OS.get_environment("WORLD_MENU_TEST") == "1" and not visible:
		_auto_ms += int(delta * 1000.0)
		if _auto_ms > 12000:
			open()
			var want := OS.get_environment("WORLD_MENU_TAB")
			if want.is_valid_int() and _tabs != null:
				_tabs.current_tab = clampi(want.to_int(), 0,
					_tabs.get_tab_count() - 1)
	if not visible:
		return
	# Four times a second, and a no-op unless something actually changed.
	# This used to run every frame and rebuild every row from scratch.
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	_refresh()
