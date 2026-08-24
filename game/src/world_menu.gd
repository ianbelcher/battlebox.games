class_name WorldMenu
extends Control
## The WORLD menu (G): everything belonging to the whole table rather
## than to one player. Per-player things (blocks, characters) live in
## PlayerHud.
##
## Tabs follow what each thing actually IS, not which code owns it, and
## they are in the order the decisions are made:
##   Game    creative or battle royale, plus that mode's settings. FIRST,
##           because the mode is what gives the rest of this menu meaning
##           — and, as modes are added, what decides which tabs exist.
##   Map     what world you're in and how play works in it — the map, its
##           size, whether flying is on. True in every mode.
##   Players who's here, their names, teams, and computer players.
##   Audio   talking to each other, and how loud everything is. Its own
##           tab because it was under "Video", where nobody looked: a
##           child hunting for voice chat is not going to open a tab
##           called Video, and volume was never a video setting either.
##   Video   how the world is drawn, and what this machine is running.
##   Credits
##
## There is no Scores tab and no Help tab. Opening this menu FREEZES
## everyone at the table, so it is the wrong place to read a scoreboard or
## look up a control: both now live in each player's own menu, which only
## stops the player who opened it. Scores also only make sense in a mode
## that keeps score — see PlayerHud._page_visible.
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

var world: Node = null

var _panel: PanelContainer
var _tabs: TabContainer
var _players_box: VBoxContainer
var _map_row: HBoxContainer
var _saved_label: Label
var _saved_row: HBoxContainer
var _server_edit: LineEdit
var _mode_btns: Dictionary = {}
var _length_btns: Dictionary = {}
var _size_btns: Dictionary = {}
var _fly_btns: Dictionary = {}
var _battle_only: Array = []
## Shown in any mode with knockouts (battle royale AND capture the flag).
var _fight_only: Array = []
var _ctf_only: Array = []
var _drop_btns: Dictionary = {}
var _target_btns: Dictionary = {}
var _revive_btns: Dictionary = {}
var _creative_only: Array = []
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

## What each list was last built from. Rebuild only when these change.
var _roster_sig := ""
var _maps_sig := ""

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
	# Rows carrying hand-painted styleboxes (team swatches, map buttons)
	# are rebuilt rather than patched — this runs on window resize only,
	# never on a timer, so it does not break the "no rebuild" rule.
	_maps_sig = ""
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
	_build_map_tab()
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
	sub.text = "Settings for everyone at this table"
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
# Map — the world, and how play works in it (both modes)
# ------------------------------------------------------------------

func _build_map_tab() -> void:
	var box := _tab("Map")
	var world_card := _section(box, "World")
	_map_row = _row(world_card)
	_saved_label = Label.new()
	_saved_label.text = "Your own worlds"
	_saved_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	world_card.add_child(_font(_saved_label, UiTheme.T_NOTE))
	_saved_row = _row(world_card)

	# Size and flying belong to the MAP: they describe how play works
	# here, in whatever mode. They used to live under Battle, which is why
	# changing them looked like it did nothing while just building.
	var size_card := _section(box, "Size of the world",
		"How far out you can roam, in blocks. Applies in both modes.")
	var size_row := _row(size_card)
	for arena in [50, 100, 150, 200, 250, 300, 350]:
		var blocks: int = arena
		var btn := _choice(size_row, str(arena), func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, -1, -1, blocks, -1))
		_min(btn, 70, 42)
		_size_btns[arena] = btn

	var fly_card := _section(box, "Flying",
		"Double-tap jump to fly. Applies in both modes.")
	var fly_row := _row(fly_card)
	for spec in [[1, "Flying allowed"], [0, "No flying"]]:
		var val: int = spec[0]
		var btn := _choice(fly_row, str(spec[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, -1, -1, -1, val))
		_min(btn, 160, 44)
		_fly_btns[val] = btn

	var server_card := _section(box, "Server",
		"The game connects here by itself on start-up.")
	var server_row := _row(server_card)
	_server_edit = LineEdit.new()
	_server_edit.text = Game.server_url()
	_server_edit.focus_mode = Control.FOCUS_ALL
	_server_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_min(_server_edit, 300, 46)
	_font(_server_edit, UiTheme.T_BODY)
	server_row.add_child(_server_edit)
	var use := _button("Use this server", func() -> void:
		var url := _server_edit.text.strip_edges()
		if url.is_empty():
			return
		if not url.begins_with("ws://") and not url.begins_with("wss://"):
			url = "ws://" + url
		Game.set_server_url(url)
		close()
		# Dropping the link is enough — main.gd shows the reconnecting
		# banner and dials the new address by itself.
		Net.disconnect_now())
	_min(use, 200, 46)
	server_row.add_child(use)

func _refresh_maps() -> void:
	if _map_row == null:
		return
	var current: String = str(world.client_world) if world != null else ""
	var listed := ""
	if world != null:
		for entry in world.map_list:
			listed += str(entry.key) + ","
	var sig := current + "|" + listed
	if sig == _maps_sig:
		return
	_maps_sig = sig
	for child in _map_row.get_children():
		child.queue_free()
	for child in _saved_row.get_children():
		child.queue_free()
	for choice in [["classic", "Island"], ["desert", "Desert"], ["isles", "Isles"],
			["castles", "Castles"], ["city", "City"], ["sky", "Skylands"],
			["space", "Space"]]:
		_map_row.add_child(_map_button(str(choice[0]), str(choice[1])))
	var have: bool = world != null and not world.map_list.is_empty()
	_saved_label.visible = have
	_saved_row.visible = have
	if have:
		for entry in world.map_list:
			_saved_row.add_child(_map_button(str(entry.key), str(entry.name)))

func _map_button(key: String, label: String) -> Button:
	var btn := _button(label, func() -> void:
		if Game.world != null:
			Game.world.sv_select_world.rpc_id(1, key))
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_min(btn, 90, 46)
	if world != null and key == world.client_world:
		_mark(btn, true)
	return btn

# ------------------------------------------------------------------
# Game — what kind of game this is
# ------------------------------------------------------------------

func _build_game_tab() -> void:
	var box := _tab("Game")
	var mode_card := _section(box, "How are we playing?",
		"Just building is the calm one: no storm, no hearts, nothing can hurt you.")
	var mode_row := _row(mode_card)
	for spec in [["creative", "🔨  Just building"], ["battle", "🏆  Battle royale"],
			["ctf", "⚑  Capture the flag"],
			["holdout", "🛡  Last flag"]]:
		var key := str(spec[0])
		var btn := _choice(mode_row, str(spec[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_set_mode.rpc_id(1, key), UiTheme.T_TITLE - 8)
		_min(btn, 150, 62)
		_mode_btns[key] = btn

	# Creative has no settings of its own, which left this tab as one row
	# of buttons above half a screen of nothing. Say what the mode IS
	# instead: the space is doing work, and a child reading it learns what
	# the other button would change.
	var calm_group := VBoxContainer.new()
	calm_group.add_theme_constant_override("separation", _s(8))
	box.add_child(calm_group)
	_creative_only.append(calm_group)
	var calm := _section(calm_group, "What just building means")
	for line in ["Nothing can hurt you — no hearts, no storm, no timer.",
			"Everyone builds in the same world, and it lasts until the "
				+ "server restarts — nothing is saved to disk.",
			"The map, how big it is and whether you can fly are on the Map tab.",
			"Switch to Battle royale for teams, weapons and the shrinking storm."]:
		var bullet := Label.new()
		bullet.text = "•   " + str(line)
		bullet.add_theme_color_override("font_color", UiTheme.INK_DIM)
		bullet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		calm.add_child(_font(bullet, UiTheme.T_LABEL))

	# Knockouts work the same way in every mode that HAS them, so this one
	# sits above the per-mode settings and is shown for both.
	var ko_group := VBoxContainer.new()
	ko_group.add_theme_constant_override("separation", _s(8))
	box.add_child(ko_group)
	_fight_only.append(ko_group)
	var ko_card := _section(ko_group, "When you are knocked out",
		"Dropping is off by default: someone who found a blaster keeps it.")
	var ko_row := _row(ko_card)
	for spec2 in [[0, "Keep your weapons"], [1, "Drop them where you fell"]]:
		var drop_val: int = spec2[0]
		var btn2 := _choice(ko_row, str(spec2[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_ctf_config.rpc_id(1, -1, -1, drop_val))
		_min(btn2, 150, 44)
		_drop_btns[drop_val] = btn2

	# Capture-the-flag-only settings.
	var ctf_group := VBoxContainer.new()
	ctf_group.add_theme_constant_override("separation", _s(8))
	box.add_child(ctf_group)
	_ctf_only.append(ctf_group)
	var ctf_card := _section(ctf_group, "Capturing",
		"Touch another team's flag to score. There is no clock — the round "
		+ "ends when someone reaches the target.")
	var target_row := _row(ctf_card)
	for t in [1, 3, 5, 10]:
		var target_val: int = t
		var btn3 := _choice(target_row, "First to %d" % t, func() -> void:
			if Game.world != null:
				Game.world.sv_ctf_config.rpc_id(1, -1, target_val, -1))
		_min(btn3, 96, 44)
		_target_btns[target_val] = btn3
	# Keep this note SHORT. It is one label in a card that grows to fit it,
	# so a long sentence here stretches the whole menu panel out past the
	# edge of the screen. Four lines of explanation used to live here and
	# it made the modal unusable.
	var rev_card := _section(ctf_group, "Getting back up",
		"Fly home and touch your own flag.")
	var rev_row := _row(rev_card)
	for spec3 in [[1, "Team-mates can pick you up too"],
			[0, "Only flying home brings you back"]]:
		var rev_val: int = spec3[0]
		var btn4 := _choice(rev_row, str(spec3[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_ctf_config.rpc_id(1, rev_val, -1, -1))
		_min(btn4, 170, 44)
		_revive_btns[rev_val] = btn4

	# Battle-only settings are hidden outright in creative rather than
	# greyed out — one less thing for a child to poke at.
	var len_group := VBoxContainer.new()
	len_group.add_theme_constant_override("separation", _s(8))
	box.add_child(len_group)
	_battle_only.append(len_group)
	var len_card := _section(len_group, "How long a battle lasts",
		"Only used in battle royale. The world's size and flying live on the Map tab.")
	var len_row := _row(len_card)
	for preset in [[3, "3 min"], [5, "5 min"], [8, "8 min"], [60, "Unlimited"]]:
		var minutes: int = preset[0]
		var btn := _choice(len_row, str(preset[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, minutes, -1, -1, -1))
		_min(btn, 120, 46)
		_length_btns[minutes] = btn

# ------------------------------------------------------------------
# Players
# ------------------------------------------------------------------

func _build_players_tab() -> void:
	var box := _tab("Players")
	_build_invite_card(box)
	_build_flying_card(box)
	var manage_card := _section(box, "Teams and computer players")
	# Two per row, not four: at four across, "Add a computer player" was
	# wider than its column and lost its last word. Plain ASCII +/− on
	# purpose too — the full-width ＋／－ glyphs are missing from the
	# bundled font and rendered as tofu boxes.
	var team_row := _row(manage_card)
	var bot_row := _row(manage_card)
	for spec in [["+  Add a team", "add_team", 0],
			["−  Remove a team", "remove_team", 0],
			["+  Add a computer player", "add_bot", 1],
			["−  Remove a computer player", "remove_bot", 1]]:
		var manage: HBoxContainer = bot_row if int(spec[2]) == 1 else team_row
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
	# The world's flying setting is in here too, because it is the DEFAULT
	# every player follows until they are singled out — flip it and every
	# row in the Fly column changes without a single roster entry moving.
	var out := "t%d|f%s|" % [teams,
		world.client_fly if world != null else false]
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
	# name | one cell per team | can-fly | remove
	grid.columns = team_count + 3
	grid.add_theme_constant_override("h_separation", _s(6))
	grid.add_theme_constant_override("v_separation", _s(6))
	_players_box.add_child(grid)

	var cell_w := int(clampf(480.0 / float(team_count), 30.0, 76.0))
	var counts := _team_counts(team_count)
	grid.add_child(_min(Control.new(), 210, 0))
	for t in team_count:
		grid.add_child(_team_header(t, counts[t], cell_w))
	var fly_head := Label.new()
	fly_head.text = "Fly"
	fly_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fly_head.add_theme_color_override("font_color", UiTheme.INK_DIM)
	grid.add_child(_font(fly_head, UiTheme.T_NOTE))
	grid.add_child(Control.new())
	for id_v in ids:
		_add_player_row(grid, str(id_v), team_count, cell_w)

## WHO CAN FLY. Groups first, because that is how it gets used: hand it to
## every computer player, then take it off the ones on Red. Doing that one
## player at a time in a room of fifty is not something anybody would sit
## through — but the column in the roster below is there for when you want
## exactly one child to be able to float out of trouble.
func _build_flying_card(box: Control) -> void:
	var card := _section(box, "Who can fly",
		"Double-tap jump to fly. Everyone follows the world's setting "
		+ "(Map tab) until they are given their own answer here.")
	var everyone := _row(card)
	for spec in [["Everyone", "all", true], ["Nobody", "all", false],
			["All computers", "bots", true], ["No computers", "bots", false]]:
		# Wide enough for the longest of them. At 150 "No computers" lost
		# its last letter and read as "No computer", which is a different
		# and wrong instruction.
		var scope := str(spec[1])
		var on: bool = spec[2]
		var btn := _button(str(spec[0]), func() -> void:
			if Game.world != null:
				Game.world.sv_set_fly.rpc_id(1, scope, -1, on)
			Sfx.play("pop", -6.0))
		_min(btn, 178, 44)
		everyone.add_child(btn)

	var teams := _row(card)
	var team_count: int = Game.world.client_team_names.size() if Game.world != null else 0
	for t in team_count:
		var team_i := t
		# One button per team that turns the whole team ON unless it
		# already is, in which case it turns the whole team OFF. A single
		# button rather than a pair: with five teams a pair each is ten
		# buttons for a thing a grown-up presses twice a game.
		var btn := _button(_team_name(team_i), func() -> void:
			if Game.world == null:
				return
			var all_flying := true
			var any_there := false
			for id: String in Game.roster.keys():
				if int(Game.roster[id].get("team", -1)) != team_i:
					continue
				any_there = true
				if not Game.world.fly_allowed_for(id):
					all_flying = false
			if not any_there:
				return
			Game.world.sv_set_fly.rpc_id(1, "team", team_i, not all_flying)
			Sfx.play("pop", -6.0))
		btn.tooltip_text = "Give this team flight, or take it away"
		var swatch: Color = WorldNode.TEAM_COLORS[team_i % WorldNode.TEAM_COLORS.size()]
		btn.add_theme_color_override("font_color", swatch)
		_min(btn, 96, 44)
		teams.add_child(btn)

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
	grid.add_child(_fly_cell(id))
	var kick := _button("✕", func() -> void:
		Game.sv_kick_player.rpc_id(1, id)
		Sfx.play("pop", -6.0), UiTheme.T_BODY)
	kick.tooltip_text = "Remove this player"
	kick.add_theme_color_override("font_color", UiTheme.DANGER)
	kick.add_theme_color_override("font_hover_color", Color.WHITE)
	_min(kick, 46, 44)
	grid.add_child(kick)

## One player's own answer, in the roster where their name is. Shows what
## is true for them right now — including when that is only because of the
## world's setting — so the column can be read down rather than worked out.
func _fly_cell(id: String) -> Button:
	var can: bool = Game.world.fly_allowed_for(id) if Game.world != null else false
	var cell := _button("✈" if can else "·", func() -> void:
		if Game.world != null:
			Game.world.sv_set_fly.rpc_id(1, "one", -1, not can, id)
		Sfx.play("pop", -6.0), UiTheme.T_BODY)
	cell.tooltip_text = "This player can fly" if can else "This player cannot fly"
	cell.add_theme_color_override("font_color",
		UiTheme.ACCENT if can else UiTheme.INK_FAINT)
	_min(cell, 46, 44)
	return cell

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
		_maps_sig = ""
		_roster_sig = ""
	_refresh_maps()
	_refresh_players()
	if world == null:
		return
	for key: String in _mode_btns:
		_mark(_mode_btns[key], key == world.client_mode)
	for minutes: int in _length_btns:
		_mark(_length_btns[minutes], minutes == world.client_minutes)
	for arena: int in _size_btns:
		_mark(_size_btns[arena], arena == world.client_size)
	for val: int in _fly_btns:
		_mark(_fly_btns[val], (val == 1) == world.client_fly)
	var battling: bool = world.client_mode == "battle"
	var ctf: bool = world.flag_mode()
	for node in _battle_only:
		if is_instance_valid(node):
			(node as Control).visible = battling
	for node in _ctf_only:
		if is_instance_valid(node):
			(node as Control).visible = ctf
	for node in _fight_only:
		if is_instance_valid(node):
			(node as Control).visible = battling or ctf
	for node in _creative_only:
		if is_instance_valid(node):
			(node as Control).visible = not (battling or ctf)
	for val: int in _drop_btns:
		_mark(_drop_btns[val], (val == 1) == world.client_drop)
	for val: int in _revive_btns:
		_mark(_revive_btns[val], (val == 1) == world.client_ctf_revive)
	for val: int in _target_btns:
		_mark(_target_btns[val], val == world.client_ctf_target)

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
