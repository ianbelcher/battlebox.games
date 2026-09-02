class_name PlayerHud
extends Control
## Per-player overlay inside their split-screen cell: name chip (click the
## swatch to change your look, click the name to type a new one), treasure
## counter, and the block hotbar along the bottom.

var slot := -1
var world: Node = null

## Hat swatch colors: the hat itself is 3D, so the chip just needs a
## distinct color per index so clicks visibly cycle something.
const HAT_CHIP_COLORS: Array[Color] = [
	Color("8d6748"), Color("ffd166"), Color("f0b429"), Color("4a9df8"),
	Color("ff9ff3"), Color("1dd1a1"), Color("f5f6fa"),
]

var _name_label: Label
var _name_edit: LineEdit
var _treasure_label: Label
var _storm_label: Label
## The card the corner notice sits on, and the one-off message currently
## being shown in it (empty when the match clock owns the corner).
var _note_card: PanelContainer
var _news := ""
var _news_t := 0.0
var _death_note: Label
## The colour draining out of the screen while you are out of the fight.
var _grey: ColorRect
var _grey_amount := 0.0
## This cell's camera, so a point in the world can be turned into a point
## on this screen. Handed over by SplitScreen.
var cam: Camera3D = null
var _death_t := 0.0
var _was_down := false
var _was_out := false
## Set once the whole team is out and we have been lifted clear.
var _team_gone_lifted := false
var _heart_cells: Array = []
var _selected_label: Label
var _picker: BlockPicker
var _pickers: Array = []
var _menu_slots_row: HBoxContainer
var _menu_slot_buttons: Array = []

func _uscale() -> float:
	# Scale from THIS HUD's size (each split-screen cell has its own), not
	# the OS window — fullscreen vs windowed must not change proportions.
	var w := size.x
	if w < 50.0:
		w = float(DisplayServer.window_get_size().x)
	return clampf(w / 1100.0, 0.75, 3.0)
var _char_buttons: Dictionary = {}
var _char_grid: GridContainer
var _char_scroll: ScrollContainer
var _char_cursor := 0
var _name_chip: Label
var _menu: PanelContainer
var _menu_dim: ColorRect
var _menu_shell: VBoxContainer
var _menu_who: Label
var _menu_scale := 1.0

## The radar and the big map, drawn for this seat. See mini_map.gd.
var map: MiniMap
# One flat row of tabs, LB/RB steps along it: Tools, Building, Natural,
# Colored, Functional, Special, Kits — and then your Character, which is
# a tab like any other (it used to hang off LB, which stole the button
# the picker needs to change tabs).
var _groups: TabContainer
var _build_tabs: TabContainer
var _game_tabs: TabContainer
var _opt_tabs: TabContainer
var _char_tabs: TabContainer
var _video_tabs: TabContainer
## PAGE NUMBERS ARE POSITIONS IN THE STRIP, so they move when the strip
## does. Tools, Build, Kits, then Character, Scores, Map. It was seven
## pickers and these read 7/8/9; collapsing the build pages to three moved
## every one of them, and a stale index here does not error — it silently
## polls the wrong page, which is the sort of bug you find by wondering
## why the map will not scroll.
const PAGE_CHARACTER := 3
const PAGE_SCORES := 4
const PAGE_MAP := 5
const _PAGES := [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5]]
var _prev_picker := false
var _prev_menu := false


var _chip: PanelContainer
var _hotbar: HBoxContainer
var _chips: Array = []
var _last_index := -1
var _last_style := -1
var _last_size := Vector2(-1, -1)
var _last_held := ""
var _slots_dirty := true
## What the eight slots held last time they were drawn. Any change repaints.
var _last_slots_sig := ""
var _prev_slot_pick_menu := -1
var _menu_tab_latch := false
var _preview_viewport: SubViewport
var _preview_avatar: Node3D
var _preview_count: Label
var _fit_label: Label
var _preview_angle := PI
var _last_tab := 1
var _tab_guard := false
var _storm_tint: ColorRect
var _water_tint: ColorRect
var _autoopened := false
var _autopicked := false
var _autopick_checked := false
var _crosshair: Label
var _storm_arrow: Label
var _revive_ring: ReviveRing

func _us(n: int) -> int:
	return int(n * clampf(DisplayServer.window_get_size().x / 1100.0, 1.15, 3.0))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# So a headless run can count them and prove the interface was built.
	add_to_group("player_hud")
	# FIRST, AND THAT IS THE WHOLE POINT OF IT. This shader reads what has
	# already been drawn, so it drains everything BEFORE it and nothing
	# after. Built first, that is the world and only the world: the map,
	# the hotbar and the hearts keep their colours.
	#
	# It used to be built half way down, which took the map with it — and
	# a grey map is exactly the wrong thing to hand somebody who has just
	# been knocked out in capture the flag and needs to find their own
	# base. Getting lost in Isles was this line's fault.
	_build_grey_wash()
	map = MiniMap.new(self)
	_build_identity_chip()
	_build_hotbar()
	_build_menu()
	_build_revive_ring()
	_build_center_note()
	_build_storm_line()
	_build_death_wash()
	_build_name_chip()
	_build_score_column()
	_build_capture_fade()
	_build_crosshair()
	_build_picker_pages()

## Top-left: the name-and-treasures chip.
func _build_identity_chip() -> void:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.72)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	chip.add_theme_stylebox_override("panel", style)
	chip.position = Vector2(10, 10)
	_chip = chip
	add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", _us(22))
	_name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_edit_name())
	row.add_child(_name_label)
	_treasure_label = Label.new()
	_treasure_label.add_theme_font_size_override("font_size", _us(22))
	_treasure_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(_treasure_label)
	_name_label.visible = false


## The bottom strip: eight slots, a heart over each, and the status
## line under them.
func _build_hotbar() -> void:
	# Bottom: hotbar, pinned to the screen bottom and growing upward so it
	# can never slide off-screen whatever lives above it.
	var bar_stack := VBoxContainer.new()
	bar_stack.add_theme_constant_override("separation", 2)
	bar_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar_stack.offset_bottom = -26
	add_child(bar_stack)
	var bar_panel := PanelContainer.new()
	bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.04, 0.05, 0.08, 0.6)
	bar_style.set_corner_radius_all(10)
	bar_style.set_content_margin_all(6)
	bar_panel.add_theme_stylebox_override("panel", bar_style)
	bar_stack.add_child(bar_panel)
	# Eight big Minecraft-style slots; 1-8 keys (or bumpers/D-pad) select.
	# Each column is heart-over-slot in ONE VBox, so heart i sits exactly
	# above slot i at any screen size — alignment by construction.
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 2)
	bar_panel.add_child(_hotbar)
	for i in 8:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var heart := Label.new()
		heart.text = "♥"
		heart.add_theme_font_size_override("font_size", _us(17))
		heart.add_theme_color_override("font_color", Color("ff4438"))
		heart.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		heart.add_theme_constant_override("outline_size", 5)
		heart.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(heart)
		_heart_cells.append(heart)
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(52, 52)
		var icon := BlockIcon.new(0)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 7
		icon.offset_top = 7
		icon.offset_right = -7
		icon.offset_bottom = -7
		frame.add_child(icon)
		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", _us(12))
		num.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		frame.add_child(num)
		col.add_child(frame)
		_hotbar.add_child(col)
		_chips.append(frame)
	# The status bar, directly under the eight slots: what you are holding,
	# then the time and how many people are in the world.
	#
	# There WAS a label for the held item — it was built, positioned above
	# the hotbar, and its text was never once assigned, so the only way to
	# tell a Freeze Ray from a Block Sucker was the icon. And the clock and
	# player count sat up in the top-right corner, across the screen from
	# everything else you look at.
	#
	# Putting all three in one strip under the hotbar keeps the middle of
	# the screen — which is where the game is — clear.
	var status_panel := PanelContainer.new()
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color(0.04, 0.05, 0.08, 0.55)
	status_style.set_corner_radius_all(8)
	status_style.content_margin_left = 12
	status_style.content_margin_right = 12
	status_style.content_margin_top = 3
	status_style.content_margin_bottom = 3
	status_panel.add_theme_stylebox_override("panel", status_style)
	status_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar_stack.add_child(status_panel)
	_selected_label = Label.new()
	# Deliberately smaller than the hotbar it sits under. This is a status
	# line you glance at, not a headline — at the size the hotbar numbers
	# are drawn it read as the loudest thing on screen.
	_selected_label.add_theme_font_size_override("font_size", _us(11))
	_selected_label.add_theme_color_override("font_color", Color("e8d9a8"))
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_child(_selected_label)


## The tabbed menu (Esc / Start), which is also the block picker.
func _build_menu() -> void:
	# Tabbed menu (Esc / Start), also home of the block picker (E jumps
	# straight to the Blocks tab). Minecraft brains expected this.
	_menu_dim = ColorRect.new()
	_menu_dim.color = UiTheme.SCRIM
	_menu_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_dim.visible = false
	add_child(_menu_dim)
	_menu = PanelContainer.new()
	# Build and Character share one centred, fixed-width panel so neither
	# spills out of a quarter-screen split cell.
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Same theme as the Escape menu — one game, one look. See ui_theme.gd.
	_menu_scale = UiTheme.scale_for(Vector2(DisplayServer.window_get_size()))
	_menu.theme = UiTheme.build(_menu_scale)
	_menu.add_theme_stylebox_override("panel", UiTheme.panel_box(_menu_scale))
	# Fill ~90% of this player's cell whatever its size — quarter-screen
	# split or a huge fullscreen window alike.
	_menu.anchor_left = 0.1
	_menu.anchor_right = 0.9
	_menu.anchor_top = 0.08
	_menu.anchor_bottom = 0.86
	_menu.visible = false
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu)
	_groups = TabContainer.new()
	_groups.get_tab_bar().focus_mode = Control.FOCUS_NONE
	_groups.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_shell = VBoxContainer.new()
	_menu_shell.add_theme_constant_override("separation",
		UiTheme.px(12, _menu_scale))
	_menu.add_child(_menu_shell)
	_menu_shell.add_child(_build_menu_header())
	_menu_shell.add_child(_groups)
	_build_tabs = TabContainer.new()
	_build_tabs.name = "Build"
	_game_tabs = TabContainer.new()
	_game_tabs.name = "World"
	_char_tabs = _build_tabs
	_video_tabs = TabContainer.new()
	_video_tabs.name = "Video"
	# The character page is built into the SAME tab strip as the pickers.
	_opt_tabs = _build_tabs
	# Clicking a tab moves the TabContainer directly, without going through
	# _set_page — so this is the ONLY place a mouse user's arrival on a
	# page is noticed. Anything a page needs on entry has to be driven from
	# here as well, or it silently works on a gamepad and not with a mouse.
	var on_page_change := func(_t: int) -> void:
		if not _tab_guard:
			_last_tab = _current_page()
			_on_page_entered(_last_tab)
	_build_tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	# Font size comes from the shared theme — see ui_theme.gd. Overriding
	# it here is what made the two menus' tab strips different sizes.
	_groups.add_child(_build_tabs)
	_build_tabs.tab_changed.connect(on_page_change)
	_groups.tab_changed.connect(on_page_change)
	# One group, so its own tab strip is pointless.
	_groups.tabs_visible = false
	_storm_tint = ColorRect.new()
	_storm_tint.color = Color(0.9, 0.15, 0.1, 0.0)
	_storm_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_storm_tint)
	_water_tint = ColorRect.new()
	_water_tint.color = Color(0.1, 0.3, 0.6, 0.0)
	_water_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_water_tint)
	map._radar = TextureRect.new()
	map._radar.stretch_mode = TextureRect.STRETCH_SCALE
	map._radar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map._radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map._radar)
	# Three times a second, not every frame: it rebuilds a 128x128 image
	# from the chunk store, and nothing on it moves fast enough to notice.
	var radar_timer := Timer.new()
	radar_timer.wait_time = 0.3
	radar_timer.timeout.connect(func() -> void:
		map._update_radar()
		_update_clock())
	add_child(radar_timer)
	radar_timer.start()

## The ring that fills while you stand over a downed team-mate.
func _build_revive_ring() -> void:
	# Revive ring: fills while you stand over a downed team-mate, so it's
	# obvious that holding still is doing something.
	_revive_ring = ReviveRing.new()
	_revive_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_revive_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_revive_ring.visible = false
	add_child(_revive_ring)
	_storm_arrow = Label.new()
	_storm_arrow.add_theme_font_size_override("font_size", _us(30))
	_storm_arrow.add_theme_color_override("font_color", Color("ff5a4a"))
	_storm_arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_storm_arrow.add_theme_constant_override("outline_size", 8)
	_storm_arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_storm_arrow.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_storm_arrow.offset_top = _us(70)
	_storm_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storm_arrow.visible = false
	add_child(_storm_arrow)

## The big centre note: lobby countdowns and next-battle timers.
func _build_center_note() -> void:
	# Big center note for match phases (lobby countdown, next-battle).
	# THE CORNER. Everything the world wants to tell this player arrives
	# here: the match clock, and one-off news like the map having been
	# replaced. One place, so a player learns where to look once.
	#
	# It is a PANEL now, not floating outlined text. Outlined gold over a
	# bright sky at a distance is not something a child reads across a
	# room, however large the letters are — and it shared the corner with
	# the hotbar, so it was competing with the busiest part of the screen
	# on its own. A dark card behind it is what makes the size count.
	_note_card = PanelContainer.new()
	var note_bg := StyleBoxFlat.new()
	note_bg.bg_color = Color(0.05, 0.06, 0.1, 0.86)
	note_bg.set_corner_radius_all(_us(12))
	note_bg.set_content_margin_all(_us(14))
	note_bg.content_margin_left = _us(20)
	note_bg.content_margin_right = _us(20)
	note_bg.border_color = UiTheme.ACCENT
	note_bg.set_border_width_all(_us(2))
	_note_card.add_theme_stylebox_override("panel", note_bg)
	_note_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_note_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_note_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_note_card.offset_right = -_us(14)
	_note_card.offset_bottom = -_us(124)
	_note_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note_card.visible = false
	add_child(_note_card)
	_center_note = Label.new()
	# Big enough to read from across the room. This is the match clock —
	# "Next battle in 12" — and on a split screen at 26px it was smaller
	# than the hotbar numbers underneath it, so nobody ever noticed a
	# round was about to start. 42 was still losing to the sky behind it.
	# A sensible size for the frame before the first layout. The real one
	# is set in _refresh_crosshair_and_layout, which overrides this the
	# moment the cell has a size — see the note there.
	_center_note.add_theme_font_size_override("font_size", _us(34))
	_center_note.add_theme_color_override("font_color", UiTheme.ACCENT)
	_center_note.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_center_note.add_theme_constant_override("outline_size", _us(6))
	_center_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# NO WRAPPING. The card is anchored to the corner and grows leftwards,
	# so it has no width for a wrap to measure against — turning wrapping
	# on produced one letter per line down the side of the screen. Every
	# message that goes here is kept short enough not to need it.
	_center_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	_note_card.add_child(_center_note)

## The storm countdown along the top of the screen.
func _build_storm_line() -> void:
	# Storm status: always-on countdown at the top of the screen so kids
	# know exactly when it starts and how long until it's fully closed.
	_storm_label = Label.new()
	_storm_label.add_theme_font_size_override("font_size", _us(20))
	_storm_label.add_theme_color_override("font_color", Color("c9a2ff"))
	_storm_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_storm_label.add_theme_constant_override("outline_size", 5)
	_storm_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_storm_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_storm_label.offset_top = _us(38)
	_storm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storm_label.visible = false
	add_child(_storm_label)

## The colour draining out of the world while you are out of the fight.
## Built before anything else — see the note in _ready.
## This screen's player.
func _me() -> String:
	return Game.player_id(multiplayer.get_unique_id(), slot)

## NOTHING RED WHILE YOU ARE OUT OF IT, and this is the single place that
## decides it.
##
## Being knocked out has been reported as "a red surround" three times,
## and each time a different layer turned out to be the one lit: first the
## full-screen death wash, then the hurt vignette, and then — measured
## against a real knockout rather than a guess — the DAMAGE FLASH, sitting
## at its ceiling of 0.36 with the whole screen and the map underneath it
## the colour of a darkroom.
##
## They are four separate layers with four separate triggers, and fixing
## them one at a time is what took three goes. So they now all ask one
## question, and it is a rule rather than a coincidence: every one of
## these means "mind yourself, you are still in this" — a warning, and a
## warning is worthless to somebody already on the floor. What a
## knocked-out player needs is to read the map and find their way back.
##
## Snapped to zero rather than eased. These layers lerp at 0.06 a frame,
## so easing from a full red flash still paints most of a second of red
## over the one moment the player is trying to work out where to go.
func _out_of_it() -> bool:
	if world == null:
		return false
	var me := _me()
	return world.client_downed.has(me) or world.out_ids.has(me)

func _build_grey_wash() -> void:
	_grey = ColorRect.new()
	_grey.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grey.visible = false
	var grey_mat := ShaderMaterial.new()
	grey_mat.shader = load("res://shaders/knocked_out.gdshader")
	grey_mat.set_shader_parameter("amount", 0.0)
	_grey.material = grey_mat
	add_child(_grey)

## The red wash and card shown when this player goes down.
func _build_death_wash() -> void:
	# Dying deserves more than silently falling over: a red wash plus a
	# big center card, cleared after a couple of seconds.
	# NO RED WASH. There used to be a full-screen red one here for a
	# couple of seconds after going down, and it is gone: the colour
	# draining out of the world already says you are out, and the red sat
	# over the MAP as well — which is the one thing a knocked-out player
	# in capture the flag actually needs to read.
	_death_note = Label.new()
	_death_note.add_theme_font_size_override("font_size", _us(44))
	_death_note.add_theme_color_override("font_color", Color("ff5a4d"))
	_death_note.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 0.95))
	_death_note.add_theme_constant_override("outline_size", 8)
	_death_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_death_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_note.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_note.visible = false
	add_child(_death_note)

## The sliver of a chip saying whose screen this is.
func _build_name_chip() -> void:
	# Tiny name chip top-left: who this screen belongs to. No padding to
	# speak of — just a sliver of backing so it reads over terrain.
	_name_chip = Label.new()
	_name_chip.add_theme_font_size_override("font_size", _us(14))
	_name_chip.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_name_chip.add_theme_constant_override("outline_size", 3)
	var chip_bg := StyleBoxFlat.new()
	chip_bg.bg_color = Color(0.04, 0.05, 0.08, 0.7)
	chip_bg.set_content_margin_all(2)
	chip_bg.content_margin_left = 6
	chip_bg.content_margin_right = 6
	chip_bg.set_corner_radius_all(4)
	_name_chip.add_theme_stylebox_override("normal", chip_bg)
	_name_chip.position = Vector2(4, 4)
	add_child(_name_chip)
	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", _us(17))
	_score_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_score_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_score_label.add_theme_constant_override("outline_size", 5)
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_label.offset_top = _us(8)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.visible = false
	add_child(_score_label)
	_team_panel = VBoxContainer.new()
	_team_panel.add_theme_constant_override("separation", _us(1))
	_team_panel.visible = false
	add_child(_team_panel)

## The left column — the scoreline and the knockout feed — and the two
## corner tabs that say which key opens which menu.
func _build_score_column() -> void:
	# THE LEFT COLUMN: the round's scoreline, then who has been knocked
	# out. One container so the feed sits under the score rather than
	# being positioned on top of it — the two used to be separate nodes at
	# fixed coordinates, which only worked while there was one of them.
	# TWO TABS IN THE BOTTOM CORNERS, saying which key opens which menu.
	# Neither menu was discoverable at all: the world menu was on a
	# backtick and the player menu on E or Ⓧ, and nothing on screen said
	# so, so a new player had two menus they could not find. Left is the
	# table's menu, right is your own — which is also where those two
	# menus live on screen, so the corner is the signpost.
	_menu_tab_left = UiTheme.hint_row(["G", "Game menu"], _menu_scale)
	_menu_tab_left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_menu_tab_left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu_tab_left.offset_left = _us(10)
	_menu_tab_left.offset_bottom = -_us(10)
	_menu_tab_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_tab_left)
	_menu_tab_right = UiTheme.hint_row([_cap("menu"), "Your stuff"], _menu_scale)
	_menu_tab_right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_menu_tab_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_menu_tab_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu_tab_right.offset_right = -_us(10)
	_menu_tab_right.offset_bottom = -_us(10)
	_menu_tab_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_tab_right)

## The full-screen flash when a flag is captured.
func _build_capture_fade() -> void:
	# The capture fade. Last child so it covers the HUD too; the menu is
	# re-ordered above everything after this, which is what we want — a
	# fade should not hide a menu somebody has open.
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.05, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate = Color(1, 1, 1, 0)
	_fade.visible = false
	add_child(_fade)
	_left_column = VBoxContainer.new()
	_left_column.add_theme_constant_override("separation", _us(6))
	_left_column.position = Vector2(_us(10), _us(60))
	add_child(_left_column)
	_ctf_panel = VBoxContainer.new()
	_ctf_panel.add_theme_constant_override("separation", _us(1))
	_ctf_panel.visible = false
	_left_column.add_child(_ctf_panel)
	_feed_box = VBoxContainer.new()
	_feed_box.add_theme_constant_override("separation", _us(2))
	_left_column.add_child(_feed_box)
	_vignette = TextureRect.new()
	var vg := Gradient.new()
	vg.colors = PackedColorArray([Color(0.7, 0.05, 0.02, 0.0), Color(0.7, 0.05, 0.02, 0.85)])
	vg.offsets = PackedFloat32Array([0.55, 1.0])
	var vg_tex := GradientTexture2D.new()
	vg_tex.gradient = vg
	vg_tex.fill = GradientTexture2D.FILL_RADIAL
	vg_tex.fill_from = Vector2(0.5, 0.5)
	vg_tex.fill_to = Vector2(0.5, 0.0)
	_vignette.texture = vg_tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.9, 0.1, 0.05, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_damage_flash)
	_damage_arrow = Label.new()
	_damage_arrow.text = "⌃"
	_damage_arrow.add_theme_font_size_override("font_size", _us(46))
	_damage_arrow.add_theme_color_override("font_color", Color("ff3b2f"))
	_damage_arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_damage_arrow.add_theme_constant_override("outline_size", 8)
	_damage_arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_damage_arrow.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_damage_arrow.grow_vertical = Control.GROW_DIRECTION_BOTH
	_damage_arrow.visible = false
	add_child(_damage_arrow)
	_revive_hint = Label.new()
	_revive_hint.add_theme_font_size_override("font_size", _us(17))
	_revive_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_revive_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_revive_hint.add_theme_constant_override("outline_size", 5)
	_revive_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_revive_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_revive_hint.offset_top = -_us(190)
	_revive_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_revive_hint.visible = false
	add_child(_revive_hint)

## The first-person crosshair.
func _build_crosshair() -> void:
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", _us(30))
	_crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_crosshair.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_crosshair.add_theme_constant_override("outline_size", 4)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

## The picker's pages, the controls line, and the eight slots that live
## inside the menu as well as on the bar.
func _build_picker_pages() -> void:
	# The menu (and its dim) must sit ABOVE the water/storm/damage tints —
	# opening the menu underwater used to render it behind the blue wash.
	move_child(_menu_dim, get_child_count() - 1)
	move_child(_menu, get_child_count() - 1)

	_pickers = []
	# Short titles: with the character page now living in this same strip
	# there are eight tabs, and the long names overflowed into scroll
	# arrows that a five-year-old will never find.
	# THREE PAGES, not seven. Nature, Colors and Lights were three answers
	# to "what can I build with" and the split never held: snow and
	# mushrooms sat under Nature when they are colours you build with, and
	# Lights held a ladder, a bookshelf, a chest and a bed. Special is gone
	# too — four blocks do not need a page, and the ones that survived are
	# tools, so they live with the tools.
	for spec in [["Tools", "tools"], ["Build", "building"], ["Kits", "kits"]]:
		var picker := BlockPicker.new(spec[1])
		picker.name = spec[0]
		picker.picked.connect(_on_picked)
		_build_tabs.add_child(picker)
		_pickers.append(picker)
	_picker = _pickers[0]
	_build_character_tab()
	_build_scores_tab()
	_build_map_tab()
	# The controls line, the same shape the Escape menu uses.
	_menu_shell.add_child(UiTheme.hint_row([_cap("choose"), "Choose",
		_cap("tabs"), "Tabs", _cap("menu"), "Close"], _menu_scale))
	# The 8 slots live inside the menu too: click a slot, then click items.
	_menu_slots_row = HBoxContainer.new()
	_menu_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_slots_row.add_theme_constant_override("separation", int(6 * _uscale()))
	_menu_shell.add_child(_menu_slots_row)
	_menu_slots_row.visible = false  # the bottom hotbar is the real one
	for i in 8:
		var slot_btn := Button.new()
		slot_btn.focus_mode = Control.FOCUS_NONE
		slot_btn.custom_minimum_size = Vector2(_us(46), _us(46))
		var icon := BlockIcon.new(0)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		slot_btn.add_child(icon)
		var index := i
		slot_btn.pressed.connect(func() -> void:
			var player := _player()
			if player != null:
				player.selected_slot = index
				_slots_dirty = true
				Sfx.play("tick", -10.0))
		_menu_slots_row.add_child(slot_btn)
		_menu_slot_buttons.append(slot_btn)

	if world != null:
		world.local_hurt.connect(func(hurt_id: String, from_pos: Vector3) -> void:
			if hurt_id == Game.player_id(multiplayer.get_unique_id(), slot):
				_damage_t = 1.8
				_damage_from = from_pos)
		world.hearts_changed.connect(func() -> void:
			var my_hp := int(world.hearts.get(Game.player_id(
				multiplayer.get_unique_id(), slot), 8))
			if my_hp < _prev_hp:
				_damage_t = maxf(_damage_t, 1.2)
			_prev_hp = my_hp)
		world.treasures_changed.connect(_refresh_identity)
		world.survival_changed.connect(_refresh_identity)
		world.hearts_changed.connect(_refresh_identity)
		world.match_changed.connect(_on_match_changed)
		world.battle_config_changed.connect(_refresh_battle_highlights)
		world.match_score_changed.connect(_refresh_team_panel)
		world.match_score_changed.connect(_refresh_ctf_panel)
		world.flag_taken.connect(_on_flag_taken)
		world.flags_changed.connect(_refresh_ctf_panel)
		world.match_changed.connect(_refresh_ctf_panel)
		world.match_changed.connect(func() -> void:
			if world.match_phase == "SETUP" and _feed_box != null:
				for old_line in _feed_box.get_children():
					old_line.queue_free())
		world.knockout.connect(func(attacker: String, attacker_team: int,
				victim: String, victim_team: int) -> void:
			var line := RichTextLabel.new()
			line.bbcode_enabled = true
			line.fit_content = true
			line.scroll_active = false
			line.autowrap_mode = TextServer.AUTOWRAP_OFF
			line.custom_minimum_size = Vector2(_us(340), 0)
			line.add_theme_font_size_override("normal_font_size", _us(15))
			var atk_color := "#ffffff"
			if attacker_team >= 0 and attacker_team < WorldNode.TEAM_COLORS.size():
				atk_color = "#" + WorldNode.TEAM_COLORS[attacker_team].to_html(false)
			var vic_color := "#ffffff"
			if victim_team >= 0 and victim_team < WorldNode.TEAM_COLORS.size():
				vic_color = "#" + WorldNode.TEAM_COLORS[victim_team].to_html(false)
			if attacker.is_empty():
				line.text = "☁💥  [color=%s]%s[/color]" % [vic_color, victim]
			else:
				line.text = "[color=%s]%s[/color]  💥  [color=%s]%s[/color]" % [
					atk_color, attacker, vic_color, victim]
			_feed_box.add_child(line)
			# GONE AFTER TEN SECONDS. The feed only ever grew — 24 lines of
			# who knocked over whom, most of it minutes old, stacked down
			# the side of the screen over the thing you are trying to look
			# at. A knockout is news for about as long as it takes to read.
			var timer := get_tree().create_timer(FEED_SECONDS)
			timer.timeout.connect(func() -> void:
				if is_instance_valid(line):
					line.queue_free())
			if _feed_box.get_child_count() > 12:
				_feed_box.get_child(0).queue_free())
	Game.roster_changed.connect(_refresh_identity)
	_refresh_identity()


## IS THIS SEAT ON A CONTROLLER? Hints are written for whatever the person
## reading them is actually holding — telling a keyboard player to press Ⓧ
## is telling them nothing, and it was doing that to every seat.
##
## Keyed on `kind` rather than on the device id, because BotSlot and the
## fake pads used by tests both pose as GAMEPAD with a negative device.
func _on_pad() -> bool:
	var seat: InputSlot = Game.local_inputs.get(slot)
	return seat != null and seat.kind == InputSlot.Kind.GAMEPAD

## The keycap for a thing you can do, in this seat's own language.
##
## Plain letters in a pill, never the circled glyphs (Ⓐ Ⓧ). Those are a
## single character carrying a ring, a letter AND its own padding, so at
## hint size the letter inside ends up a couple of pixels across and
## unreadable — which is the whole complaint. `UiTheme.key_cap` already
## draws the badge; the text just has to say which key.
func _cap(what: String) -> String:
	match what:
		"choose":
			return "A" if _on_pad() else "Click"
		"tabs":
			return "LB  RB" if _on_pad() else "Tab"
		"menu":
			return "X" if _on_pad() else "E"
		_:
			return what

## SOMEBODY TOOK A FLAG. If it was us, hold still and fade: the trip home
## happens behind the black so it is a scene change rather than a
## teleport. The server holds the same beat and makes us untouchable for
## it, so nothing can happen to us while we cannot see.
func _on_flag_taken(id: String, _team: int, _from_team: int) -> void:
	if world == null or _fade == null:
		return
	if id != Game.player_id(multiplayer.get_unique_id(), slot):
		return
	var me := _player()
	if me != null:
		me.begin_capture_hold(CtfDirector.CTF_CAPTURE_FADE * 2.0)
	Sfx.play("collect", 0.0, 1.2)
	_fade.visible = true
	var fade := _fade.create_tween()
	fade.tween_property(_fade, "modulate:a", 1.0, CtfDirector.CTF_CAPTURE_FADE)
	fade.tween_interval(0.12)
	fade.tween_property(_fade, "modulate:a", 0.0, CtfDirector.CTF_CAPTURE_FADE)
	fade.tween_callback(func() -> void:
		if is_instance_valid(_fade):
			_fade.visible = false)

func is_ui_open() -> bool:
	return _menu != null and _menu.visible

## The picker's title block: whose menu this is on the left, how to leave
## on the right, and a rule under both. Deliberately the same shape as the
## Escape menu's header so the two read as one game.
func _build_menu_header() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.px(10, _menu_scale))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.px(12, _menu_scale))
	box.add_child(row)

	var mark := Label.new()
	mark.text = "🎒"
	mark.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_TITLE, _menu_scale))
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(titles)
	var title := Label.new()
	title.text = "YOUR STUFF"
	title.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_TITLE, _menu_scale))
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	titles.add_child(title)
	_menu_who = Label.new()
	_menu_who.text = "Blocks, kits and who you are"
	_menu_who.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_NOTE, _menu_scale))
	_menu_who.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	titles.add_child(_menu_who)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(UiTheme.hint_row([_cap("menu"), "Close"], _menu_scale))
	box.add_child(HSeparator.new())
	return box

# ---- Controller navigation over regular menu pages (not the pickers,
# they have their own grid cursor): left stick moves a highlight between
# buttons/sliders, A presses, sliders adjust with left/right. ----
var _nav_focus: Control = null
var _nav_repeat := 0.0
var _prev_nav_select := true

func _page_control(page: int) -> Control:
	var spec: Array = _PAGES[clampi(page, 0, _PAGES.size() - 1)]
	return _inner_tabs(spec[0]).get_child(spec[1])

func _poll_page_nav(input: InputSlot, delta: float) -> void:
	if input.kind == InputSlot.Kind.KEYBOARD_WASD:
		# The mouse player CLICKS: no roaming gold focus stealing WASD
		# keys (and no scaled-up "selected" look on settings rows).
		_set_nav_focus(null)
		return
	var controls: Array = []
	var root := _page_control(_current_page())
	for kind in ["BaseButton", "HSlider"]:
		for node in root.find_children("*", kind, true, false):
			if (node as Control).is_visible_in_tree():
				controls.append(node)
	if controls.is_empty():
		_set_nav_focus(null)
		return
	if _nav_focus == null or not is_instance_valid(_nav_focus) \
			or not _nav_focus.is_visible_in_tree() or not controls.has(_nav_focus):
		_set_nav_focus(controls[0])
	var dir := input.get_move_vector()
	_nav_repeat -= delta
	if dir.length() > 0.55:
		if _nav_repeat <= 0.0:
			_nav_repeat = 0.24
			if _nav_focus is HSlider and absf(dir.x) > absf(dir.y):
				var slider: HSlider = _nav_focus
				slider.value += slider.step * signf(dir.x)
				Sfx.play("tick", -14.0)
			else:
				# Snap to the dominant axis: up means screen-up, never
				# a diagonal hop to whatever sat up-and-right.
				var snapped := Vector2(signf(dir.x), 0.0) \
					if absf(dir.x) > absf(dir.y) else Vector2(0.0, signf(dir.y))
				_nav_move(controls, snapped)
	else:
		_nav_repeat = 0.0
	var select := input.is_primary_pressed()
	if select and not _prev_nav_select and _nav_focus is BaseButton:
		var btn: BaseButton = _nav_focus
		if btn.toggle_mode:
			btn.button_pressed = not btn.button_pressed
		else:
			btn.pressed.emit()
	_prev_nav_select = select

## Spatial move: nearest control mostly in the pushed direction.
## The character grid: moving IS choosing. No cursor-then-confirm dance —
## whatever you land on is who you are, and the right stick spins the
## preview so kids can look at the back of their own head.
var _char_nav_cd := 0.0

func _poll_character_nav(input: InputSlot, delta: float) -> void:
	_char_nav_cd = maxf(0.0, _char_nav_cd - delta)
	var all: Array = AvatarFactory.characters()
	if all.is_empty():
		return
	var entry := _entry()
	var current: int = all.find(str(AvatarFactory.normalize_style(
		entry.get("style")).get("who", "")))
	if current < 0:
		current = 0
	var nav := input.get_ui_vector()
	if _char_nav_cd <= 0.0 and nav.length() > 0.5:
		var step := 0
		if absf(nav.x) > absf(nav.y) * 1.35:
			step = 1 if nav.x > 0 else -1
		elif absf(nav.y) > absf(nav.x) * 1.35:
			step = 6 if nav.y > 0 else -6
		if step != 0:
			var next := clampi(current + step, 0, all.size() - 1)
			if next != current:
				_char_nav_cd = 0.16
				Game.set_local_style(slot, {"who": str(all[next])})
				Sfx.play("tick", -14.0)
				if _char_scroll != null and _char_grid != null \
						and next < _char_grid.get_child_count():
					_char_scroll.ensure_control_visible(
						_char_grid.get_child(next) as Control)
	# Right stick spins the preview.
	var spin := input.get_look_vector()
	if absf(spin.x) > 0.2:
		_preview_angle = fposmod(_preview_angle + spin.x * delta * 2.4, TAU)
		if _preview_avatar != null and is_instance_valid(_preview_avatar):
			_preview_avatar.rotation.y = _preview_angle

func _nav_move(controls: Array, dir: Vector2) -> void:
	if _nav_focus == null:
		return
	var from: Vector2 = _nav_focus.get_global_rect().get_center()
	var n := dir.normalized()
	var best: Control = null
	var best_score := INF
	for c: Control in controls:
		if c == _nav_focus:
			continue
		var to := c.get_global_rect().get_center() - from
		var along := to.dot(n)
		if along <= 4.0:
			continue
		var score := along + absf(to.cross(n)) * 5.0
		if score < best_score:
			best_score = score
			best = c
	if best != null:
		_set_nav_focus(best)
		Sfx.play("tick", -14.0)

func _set_nav_focus(c: Control) -> void:
	if _nav_focus == c:
		return
	if _nav_focus != null and is_instance_valid(_nav_focus):
		_nav_focus.modulate = Color.WHITE
	if _nav_focus != null and is_instance_valid(_nav_focus):
		_nav_focus.scale = Vector2.ONE
	_nav_focus = c
	if c != null:
		c.modulate = Color(1.5, 1.35, 0.85)
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2.ONE * 1.06
		var p: Node = c.get_parent()
		while p != null and not (p is ScrollContainer):
			p = p.get_parent()
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)

## Shut this player's menu from outside — the WORLD menu opening.
func close_menu() -> void:
	if _menu != null and _menu.visible:
		_close_menu()

func _toggle_menu(player: Player, open_tab: int) -> void:
	if _menu.visible:
		_close_menu()
		return
	# One modal at a time. Pressing E while the world menu is up used to
	# open this UNDERNEATH it; you closed the world menu and found yourself
	# still stuck in a second one you had forgotten opening.
	if Game.world_menu != null and Game.world_menu.visible:
		Game.world_menu.close()
	_menu.visible = true
	_menu_dim.visible = true
	# Which pages exist depends on the mode, and the mode can change while
	# the menu is shut, so this is settled on the way in. Guarded: hiding
	# the tab somebody is standing on fires tab_changed, which would
	# otherwise record the fallback page as "the tab they were last on".
	_tab_guard = true
	_refresh_tab_visibility()
	_tab_guard = false
	# The Tools tab stays OPEN in a battle. It used to be disabled
	# outright, so there was no way to look at — let alone switch to —
	# the weapons you had picked up. What a battle restricts is WHICH
	# ones you may choose: only the ones you are carrying.
	_build_tabs.set_tab_disabled(0, false)
	var owned: Array = []
	if world != null and world.match_phase != "IDLE":
		for entry_slot: Dictionary in player.slots:
			if str(entry_slot.kind) == "weapon":
				owned.append(int(entry_slot.id))
	_pickers[0].set_allowed(owned)
	_refresh_preview()
	player.ui_locked = true
	# picker.open() flips child visibility, which yanks the TabContainer onto
	# whichever picker was shown last (the "always opens on Kits" bug) — so
	# the pickers open FIRST and the real tab is set after, guarded so the
	# churn doesn't pollute _last_tab.
	_tab_guard = true
	# Size the chips from the PANEL, not from the whole cell: the panel is
	# 80% of a full-screen cell but 96% of a split one, so measuring the
	# cell left half-screen players with chips a third smaller than they
	# had room for.
	var span := Vector2(size.x * 0.75, size.y * 0.6)
	if _menu.size.x > 100.0:
		span = Vector2(_menu.size.x * 0.9, _menu.size.y * 0.6)
	for picker: BlockPicker in _pickers:
		picker.fit(span)
		picker.open()
	# Back to whichever tab you were last on. Opening on Building every
	# time meant anyone living in Kits or on their character page paid two
	# extra clicks every single time they opened this. `_last_tab` already
	# existed and was tracked correctly — this path just never read it.
	#
	# A forced page (open_tab >= 1) is still honoured, which is what the
	# autotest hook uses to land on a particular tab.
	if open_tab >= 1 and not _page_disabled(open_tab):
		_set_page(open_tab)
	else:
		_set_page(1 if _page_disabled(_last_tab) else _last_tab)
	_tab_guard = false
	var entry := _entry()
	if _name_edit != null and not entry.is_empty():
		_name_edit.text = str(entry.name)
	Sfx.play("tick", -8.0)

## Menu-scale pixels: the shared design unit the whole menu is drawn in.
func _ms(n: int) -> int:
	return UiTheme.px(n, _menu_scale)

## A raised surface for a group of controls, matching the Escape menu.
func _menu_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(_menu_scale))
	return card

## The character page: a roster on the left, the model on the right —
## the shape every character-select screen uses, because it works.
##
## Moving the cursor IS choosing. Kids don't get "highlight, then confirm",
## so whatever you land on is who you are, and the right stick spins the
## model so they can look at the back of their own head.
func _build_character_tab() -> void:
	var page := MarginContainer.new()
	page.name = "Character"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		page.add_theme_constant_override(side, _ms(14))
	_opt_tabs.add_child(page)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", _ms(14))
	page.add_child(split)

	# ---- left: the roster
	var left := _menu_card()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.35
	split.add_child(left)
	var grid_holder := VBoxContainer.new()
	grid_holder.add_theme_constant_override("separation", _ms(10))
	left.add_child(grid_holder)
	# No "CHOOSE A CHARACTER" heading: the tab is called Character and the
	# page is a grid of faces. Saying it a third time only cost height.
	var grid_scroll := ScrollContainer.new()
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_holder.add_child(grid_scroll)
	_char_grid = GridContainer.new()
	_char_grid.columns = 6
	_char_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_char_grid.add_theme_constant_override("h_separation", _ms(8))
	_char_grid.add_theme_constant_override("v_separation", _ms(8))
	grid_scroll.add_child(_char_grid)
	_char_scroll = grid_scroll
	for who in AvatarFactory.characters():
		var cbtn := Button.new()
		cbtn.focus_mode = Control.FOCUS_NONE
		cbtn.custom_minimum_size = Vector2(_ms(86), _ms(86))
		var icon := TextureRect.new()
		var icon_path: String = AvatarFactory.portrait_of(str(who))
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = _ms(5)
		icon.offset_top = _ms(5)
		icon.offset_right = -_ms(5)
		icon.offset_bottom = -_ms(5)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cbtn.add_child(icon)
		var pick_who := str(who)
		cbtn.pressed.connect(func() -> void:
			Game.set_local_style(slot, {"who": pick_who, "fit": pick_who})
			Sfx.play("pop", -6.0))
		_char_grid.add_child(cbtn)
		_char_buttons[pick_who] = cbtn

	# ---- right: the model, on its own plinth
	var right := _menu_card()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.custom_minimum_size = Vector2(_ms(240), 0)
	split.add_child(right)
	var char_right := VBoxContainer.new()
	char_right.add_theme_constant_override("separation", _ms(8))
	right.add_child(char_right)
	# Your name, and it is the FIELD — click it and type. There was no way
	# to change a name in the game at all: this page showed it as a label,
	# and the only rename lived in the grown-ups' menu.
	#
	# Committed on Enter and on losing focus, because a child who types a
	# new name and then clicks away has plainly finished, and losing it
	# there would be baffling.
	_name_edit = LineEdit.new()
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.max_length = 14
	_name_edit.placeholder_text = "your name"
	_name_edit.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_BODY + 4, _menu_scale))
	_name_edit.add_theme_color_override("font_color", UiTheme.ACCENT)
	_name_edit.tooltip_text = "Click to change your name"
	var commit_name := func(_arg: Variant = null) -> void:
		var typed := _name_edit.text.strip_edges()
		if typed.is_empty():
			# Refuse to become nameless; put the old one back.
			var back := _entry()
			_name_edit.text = str(back.get("name", "")) if not back.is_empty() else ""
			return
		if typed != str(_entry().get("name", "")):
			Game.set_local_name(slot, typed)
			Sfx.play("tick", -8.0)
	_name_edit.text_submitted.connect(commit_name)
	_name_edit.focus_exited.connect(func() -> void: commit_name.call(null))
	char_right.add_child(_name_edit)
	_preview_viewport = SubViewport.new()
	_preview_viewport.own_world_3d = true
	_preview_viewport.transparent_bg = true
	# STRETCHED, not fixed. A SubViewportContainer that does not stretch
	# takes the viewport's size as its MINIMUM, and a minimum of 400 design
	# units is taller than the rest of the menu's pages — so opening this
	# tab pushed the whole panel taller than its anchors and the menu
	# visibly changed size as you tabbed onto it, moving the tab strip out
	# from under the mouse. Stretching lets the page fit the panel instead
	# of the panel fit the page.
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(0, _ms(150))
	holder.add_child(_preview_viewport)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion \
				and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_preview_angle = fposmod(_preview_angle + event.relative.x * 0.012, TAU)
			if _preview_avatar != null and is_instance_valid(_preview_avatar):
				_preview_avatar.rotation.y = _preview_angle)
	char_right.add_child(holder)
	_preview_count = Label.new()
	_preview_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_count.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_NOTE, _menu_scale))
	_preview_count.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	char_right.add_child(_preview_count)
	# The outfit stepper. Every character in the pack is the same six
	# meshes, so the clothes of any one of them fit any other — this swaps
	# the torso and legs and leaves the face and arms alone.
	var fit_row := HBoxContainer.new()
	fit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fit_row.add_theme_constant_override("separation", _ms(6))
	for step: int in [-1, 1]:
		var arrow := Button.new()
		arrow.focus_mode = Control.FOCUS_NONE
		arrow.text = "◀" if step < 0 else "▶"
		arrow.add_theme_font_size_override("font_size",
			UiTheme.px(UiTheme.T_BODY, _menu_scale))
		arrow.pressed.connect(func() -> void:
			Game.cycle_local_style(slot, "fit", step)
			Sfx.play("tick", -8.0))
		if step < 0:
			fit_row.add_child(arrow)
			_fit_label = Label.new()
			_fit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_fit_label.custom_minimum_size = Vector2(_ms(96), 0)
			_fit_label.add_theme_font_size_override("font_size",
				UiTheme.px(UiTheme.T_NOTE, _menu_scale))
			fit_row.add_child(_fit_label)
		else:
			fit_row.add_child(arrow)
	char_right.add_child(fit_row)
	var spin_hint := Label.new()
	spin_hint.text = "Drag, or push the right stick, to spin"
	spin_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spin_hint.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_NOTE, _menu_scale))
	spin_hint.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	char_right.add_child(spin_hint)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.95, 2.25)
	_preview_viewport.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	_preview_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.35
	_preview_viewport.add_child(fill)

## The chosen character gets a gold RING, not a gold fill — a fill behind
## a portrait reads as "this square is a button", not "this is you".
func _mark_character(btn: Button, on: bool) -> void:
	if not is_instance_valid(btn):
		return
	if on:
		var sel := UiTheme.flat(UiTheme.SURFACE_3, UiTheme.R_CONTROL,
			_menu_scale, 3.0, UiTheme.ACCENT)
		sel.shadow_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g,
			UiTheme.ACCENT.b, 0.30)
		sel.shadow_size = _ms(10)
		for state in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(state, sel)
	else:
		for state in ["normal", "hover", "pressed"]:
			btn.remove_theme_stylebox_override(state)

## Scrolls the roster to whoever you already are. Called when the page
## appears, not when the roster changes: ensure_control_visible on a
## hidden ScrollContainer does nothing, which is why opening the menu
## used to land at character 1 with your own face 30 rows down.
func _scroll_to_character() -> void:
	if _char_scroll == null:
		return
	var who := str(AvatarFactory.normalize_style(
		_entry().get("style")).get("who", ""))
	var btn: Button = _char_buttons.get(who)
	if btn != null:
		_char_scroll.ensure_control_visible(btn)

## THE ROUND TAB IS GONE, and with it the last of the game's own settings
## that were reachable from inside it. The mode and the map went first;
## the round length was the leftover, and it is the same objection — it
## changes how the game is played, under people who are playing it. All of
## it is asked on the front page before the world exists. See
## game_setup.gd.
func _build_game_tab() -> void:
	var tab := _scrolled_tab("Players", _game_tabs)

	tab.add_theme_constant_override("separation", _us(10))
	_lobby_countdown = Label.new()
	_lobby_countdown.add_theme_font_size_override("font_size", _us(22))
	_lobby_countdown.add_theme_color_override("font_color", UiTheme.ACCENT)
	_lobby_countdown.visible = false
	tab.add_child(_lobby_countdown)
	var manage_row := HBoxContainer.new()
	manage_row.add_theme_constant_override("separation", _us(8))
	tab.add_child(manage_row)
	for spec in [["➕ Team", "add_team"], ["➖ Team", "remove_team"],
			["➕ Computer player", "add_bot"], ["➖ Computer player", "remove_bot"]]:
		var manage_btn := Button.new()
		manage_btn.focus_mode = Control.FOCUS_NONE
		manage_btn.text = str(spec[0])
		manage_btn.add_theme_font_size_override("font_size", _us(19))
		var action := str(spec[1])
		manage_btn.pressed.connect(func() -> void:
			if Game.world == null:
				return
			match action:
				"add_team": Game.world.sv_add_team.rpc_id(1)
				"remove_team": Game.world.sv_remove_team.rpc_id(1, -1)
				"add_bot": Game.world.sv_add_bot.rpc_id(1)
				"remove_bot": Game.world.sv_remove_bot.rpc_id(1, "")
			Sfx.play("tick", -8.0))
		manage_row.add_child(manage_btn)
		if action == "add_bot":
			_add_bot_btn = manage_btn
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", _us(4))
	tab.add_child(_team_box)
## A tab whose content scrolls vertically instead of overflowing.
func _scrolled_tab(tab_name: String, parent: TabContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, _us(14))
	scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(box)
	return box

func _inner_tabs(group: int) -> TabContainer:
	return [_build_tabs, _game_tabs, _char_tabs, _video_tabs][group]

func _current_page() -> int:
	for page in _PAGES.size():
		if _PAGES[page][0] == _groups.current_tab \
				and _PAGES[page][1] == _inner_tabs(_groups.current_tab).current_tab:
			return page
	return 0

func _set_page(page: int) -> void:
	var spec: Array = _PAGES[clampi(page, 0, _PAGES.size() - 1)]
	_groups.current_tab = spec[0]
	_inner_tabs(spec[0]).current_tab = spec[1]
	_on_page_entered(page)

## Whatever a page needs doing when you ARRIVE on it.
##
## Split out of _set_page because _set_page is only reached from the
## keyboard and the gamepad. Clicking a tab with the mouse moves the
## TabContainer directly and never went through any of this — which is why
## the map opened at its default 2.0 blocks-per-pixel for anybody who used
## a mouse, drawing the whole world as a small square adrift in black. It
## looked like a zoom bug and was really a "this code never ran" bug.
func _on_page_entered(page: int) -> void:
	if page == PAGE_CHARACTER:
		_scroll_to_character.call_deferred()
	elif page == PAGE_MAP:
		map._reset_map_view()


## Should this page be in the tab strip at all, right now?
##
## Written as a predicate per page rather than a flag, because the reason a
## page appears is going to differ per page as modes are added: this
## scoreboard is teams-and-knockouts, which means nothing while everyone is
## just building, and the next mode will want a scoreboard of its own
## rather than this one wearing a different hat. A new mode adds a case
## here and a page; it does not touch anything that already works.
func _page_visible(page: int) -> bool:
	match page:
		PAGE_SCORES:
			return world != null and (world.client_mode == "battle"
				or world.flag_mode())
		_:
			return true

## Apply _page_visible across the strip. Called whenever the menu opens and
## whenever the mode changes, since the mode is what the answers depend on.
func _refresh_tab_visibility() -> void:
	var showing := _current_page()
	for page in _PAGES.size():
		var spec: Array = _PAGES[page]
		var tabs := _inner_tabs(int(spec[0]))
		var idx := int(spec[1])
		if idx < tabs.get_tab_count():
			tabs.set_tab_hidden(idx, not _page_visible(page))
	# Standing on a page that just vanished leaves the panel blank, so
	# step off it rather than leave the player looking at nothing.
	if not _page_visible(showing):
		_set_page(1)

func _page_disabled(page: int) -> bool:
	if not _page_visible(page):
		return true
	var spec: Array = _PAGES[clampi(page, 0, _PAGES.size() - 1)]
	return _inner_tabs(spec[0]).is_tab_disabled(spec[1])

func _add_section(tab: Control, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", _us(16))
	lbl.add_theme_color_override("font_color", UiTheme.ACCENT)
	tab.add_child(lbl)
	tab.add_child(HSeparator.new())

## The league table, in the player's OWN menu — the end-of-match panel
## is gone in ten seconds and the Escape menu belongs to the grown-up
## sorting the table out. This is where a kid actually looks.
var _scores_box: VBoxContainer
var _scores_sig := ""

## Capture the flag's table: taken, lost, score — ordered by who is
## winning — and underneath, who actually ran the flags in.
func _refresh_ctf_scores() -> void:
	var sig := "ctf|%s|%s|%s" % [str(world.ctf_caps), str(world.ctf_lost),
		str(world.ctf_player_caps)]
	if sig == _scores_sig:
		return
	_scores_sig = sig
	for child in _scores_box.get_children():
		child.queue_free()

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _ms(10))
	_scores_box.add_child(head)
	for col in [["TEAM", 150], ["TAKEN", 80], ["LOST", 80], ["SCORE", 80]]:
		var h := Label.new()
		h.text = str(col[0])
		h.custom_minimum_size = Vector2(_ms(int(col[1])), 0)
		h.add_theme_font_size_override("font_size",
			UiTheme.px(UiTheme.T_NOTE, _menu_scale))
		h.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		head.add_child(h)

	var teams: Array = []
	for t in int(world.team_count):
		teams.append(t)
	teams.sort_custom(func(a: int, b: int) -> bool:
		return int(world.ctf_scores.get(a, 0)) > int(world.ctf_scores.get(b, 0)))
	for t: int in teams:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _ms(10))
		_scores_box.add_child(row)
		var tint: Color = WorldNode.TEAM_COLORS[t] \
			if t < WorldNode.TEAM_COLORS.size() else Color.WHITE
		for cell in [[str(world.client_team_names[t]) \
					if t < world.client_team_names.size() else "Team %d" % (t + 1), 150],
				[str(int(world.ctf_caps.get(t, 0))), 80],
				[str(int(world.ctf_lost.get(t, 0))), 80],
				[str(int(world.ctf_scores.get(t, 0))), 80]]:
			var lbl := Label.new()
			lbl.text = str(cell[0])
			lbl.custom_minimum_size = Vector2(_ms(int(cell[1])), 0)
			lbl.add_theme_font_size_override("font_size",
				UiTheme.px(UiTheme.T_BODY, _menu_scale))
			lbl.add_theme_color_override("font_color", tint)
			row.add_child(lbl)

	var target := Label.new()
	target.text = "First to %d wins." % int(world.ctf_target)
	target.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_NOTE, _menu_scale))
	target.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	_scores_box.add_child(target)

	# Who did it. A capture is a whole-team point, but the run itself is
	# somebody's, and a nine-year-old wants to see their own name here.
	var runners: Array = []
	for pid: String in world.ctf_player_caps.keys():
		runners.append(pid)
	runners.sort_custom(func(a: String, b: String) -> bool:
		return int(world.ctf_player_caps.get(a, 0)) \
			> int(world.ctf_player_caps.get(b, 0)))
	if not runners.is_empty():
		_scores_box.add_child(_scores_head("FLAGS TAKEN BY"))
		for pid: String in runners:
			var who := str(Game.roster.get(pid, {}).get("name", "?"))
			var line := Label.new()
			line.text = "%s — %d" % [who, int(world.ctf_player_caps.get(pid, 0))]
			line.add_theme_font_size_override("font_size",
				UiTheme.px(UiTheme.T_BODY, _menu_scale))
			_scores_box.add_child(line)

func _build_scores_tab() -> void:
	var page := MarginContainer.new()
	page.name = "Scores"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		page.add_theme_constant_override(side, _ms(14))
	_opt_tabs.add_child(page)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_scores_box = VBoxContainer.new()
	_scores_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scores_box.add_theme_constant_override("separation", _ms(10))
	scroll.add_child(_scores_box)

func _refresh_scores_tab() -> void:
	if _scores_box == null or world == null:
		return
	# Capture the flag keeps a completely different score — flags in and
	# flags out, not games won and knockouts — so it gets its own table
	# rather than the battle one relabelled. The next mode will want its
	# own again; this is where that goes.
	if world.flag_mode():
		_refresh_ctf_scores()
		return
	var sig := "%d|%s|%s" % [int(world.matches_played), str(world.team_wins),
		str(world.player_frags)]
	if sig == _scores_sig:
		return
	_scores_sig = sig
	for child in _scores_box.get_children():
		child.queue_free()
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", _ms(16))
	_scores_box.add_child(split)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_theme_constant_override("separation", _ms(5))
	split.add_child(left)
	left.add_child(_scores_head("GAMES WON"))
	var teams: Array = []
	for t in int(world.team_count):
		teams.append(t)
	teams.sort_custom(func(a: int, b: int) -> bool:
		return int(world.team_wins.get(a, 0)) > int(world.team_wins.get(b, 0)))
	for t: int in teams:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _ms(8))
		left.add_child(row)
		var team_label := Label.new()
		team_label.text = str(world.client_team_names[t]) \
			if t < world.client_team_names.size() else str(t + 1)
		team_label.custom_minimum_size = Vector2(_ms(110), 0)
		team_label.add_theme_font_size_override("font_size",
			UiTheme.px(UiTheme.T_LABEL, _menu_scale))
		if t < WorldNode.TEAM_COLORS.size():
			team_label.add_theme_color_override("font_color", WorldNode.TEAM_COLORS[t])
		row.add_child(team_label)
		var wins := Label.new()
		wins.text = str(int(world.team_wins.get(t, 0)))
		wins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		wins.add_theme_font_size_override("font_size",
			UiTheme.px(UiTheme.T_BODY, _menu_scale))
		wins.add_theme_color_override("font_color", UiTheme.ACCENT)
		wins.custom_minimum_size = Vector2(_ms(50), 0)
		row.add_child(wins)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_theme_constant_override("separation", _ms(5))
	split.add_child(right)
	right.add_child(_scores_head("KNOCKOUTS"))
	var names: Array = world.player_frags.keys()
	if names.is_empty():
		var none := Label.new()
		none.text = "Nobody has knocked anybody out yet."
		none.add_theme_font_size_override("font_size",
			UiTheme.px(UiTheme.T_LABEL, _menu_scale))
		none.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		right.add_child(none)
		return
	names.sort_custom(func(a: String, b: String) -> bool:
		var ta := int(world.player_frags[a].get("total", 0))
		var tb := int(world.player_frags[b].get("total", 0))
		if ta != tb:
			return ta > tb
		return a < b)
	# THREE columns, sized to their contents, hugged to the left. It was
	# four full-width columns, which left a chasm between the names and
	# the numbers. The team is the NAME'S COLOUR now rather than a column
	# of its own — you know what colour your team is.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", _ms(18))
	grid.add_theme_constant_override("v_separation", _ms(4))
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(grid)
	for head_text in ["Player", "This game", "Total"]:
		var head := Label.new()
		head.text = str(head_text)
		head.add_theme_font_size_override("font_size",
			UiTheme.px(UiTheme.T_NOTE, _menu_scale))
		head.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		if head_text != "Player":
			head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(head)
	for who: String in names:
		var row_data: Dictionary = world.player_frags[who]
		var team := int(row_data.get("team", -1))
		var tint: Color = WorldNode.TEAM_COLORS[team] \
			if team >= 0 and team < WorldNode.TEAM_COLORS.size() else UiTheme.INK
		for spec in [[who, HORIZONTAL_ALIGNMENT_LEFT, tint],
				[str(int(row_data.get("last", 0))), HORIZONTAL_ALIGNMENT_RIGHT, tint],
				[str(int(row_data.get("total", 0))), HORIZONTAL_ALIGNMENT_RIGHT,
					UiTheme.INK_FAINT]]:
			var cell := Label.new()
			cell.text = str(spec[0])
			cell.horizontal_alignment = spec[1]
			cell.add_theme_font_size_override("font_size",
				UiTheme.px(UiTheme.T_LABEL, _menu_scale))
			cell.add_theme_color_override("font_color", spec[2])
			grid.add_child(cell)

func _scores_head(text: String) -> Label:
	var head := Label.new()
	head.text = text
	head.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_HEADING, _menu_scale))
	head.add_theme_color_override("font_color", UiTheme.INK_DIM)
	return head

var _map_label: Label

func _build_map_tab() -> void:
	var page := MarginContainer.new()
	page.name = "Map"
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		page.add_theme_constant_override(side, _ms(14))
	_opt_tabs.add_child(page)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _ms(8))
	page.add_child(box)
	map._map_tex = TextureRect.new()
	map._map_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map._map_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map._map_tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map._map_tex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map._map_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	map._map_tex.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion \
				and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			map._map_centre -= event.relative * map._map_zoom
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				map._map_zoom = clampf(map._map_zoom * 0.8, map._map_fit * 0.12, map._map_fit)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				map._map_zoom = clampf(map._map_zoom * 1.25, map._map_fit * 0.12, map._map_fit))
	box.add_child(map._map_tex)
	_map_label = Label.new()
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_label.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_NOTE, _menu_scale))
	_map_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	_map_label.text = "Right stick moves · left stick up/down zooms · drag to pan"
	box.add_child(_map_label)







func _refresh_preview() -> void:
	if _preview_viewport == null:
		return
	if _preview_avatar != null:
		_preview_avatar.queue_free()
	var entry := _entry()
	# The size is the CONTAINER's business now (it stretches), so nothing
	# here touches it. Setting it here is what used to force the menu panel
	# taller on this tab than on any other.
	_preview_avatar = AvatarFactory.build_character(entry.get("style", {}))
	_preview_avatar.position = Vector3(0, 0, 0)
	_preview_avatar.rotation.y = _preview_angle
	_preview_viewport.add_child(_preview_avatar)
	# Don't fight someone who is mid-type: only refill the field when it is
	# not the thing they are currently editing.
	if _name_edit != null and not entry.is_empty() and not _name_edit.has_focus():
		_name_edit.text = str(entry.name)
	var style := AvatarFactory.normalize_style(entry.get("style"))
	if _preview_count != null:
		var all: Array = AvatarFactory.characters()
		var at := all.find(str(style.who))
		_preview_count.text = "Character %d of %d" % [at + 1, all.size()] \
			if at >= 0 else ""
	if _fit_label != null:
		var outfits: Array = AvatarFactory.outfits()
		var wearing := outfits.find(str(style.fit))
		_fit_label.text = "own clothes" if str(style.fit) == str(style.who) \
			else "outfit %d" % (wearing + 1)

## Personal radar: terrain around YOU, plus blips — crates gold, other
## players team-colored, yourself white. One per player, centered on them.
## Show the ring over the nearest downed team-mate being picked up.
func _update_revive_ring(player: Player) -> void:
	if _revive_ring == null or world == null or player == null:
		return
	# WHOSE REVIVE IS THIS? The ring used to show for ANY player within 12
	# blocks who had progress on them, which meant it lit up on your screen
	# because somebody else was being picked up nearby — or, once the flag
	# could revive you, because a team-mate was tagging in at a flag you
	# happened to be standing at. Alive, in no trouble at all, watching a
	# "reviving" ring fill.
	#
	# There are exactly two things it may mean, and they are both about
	# YOU: somebody is picking you up, or you are picking somebody up.
	var me := Game.player_id(multiplayer.get_unique_id(), slot)
	var best := 0.0
	var found := false
	if world.revive_progress.has(me):
		best = float(world.revive_progress[me])
		found = true
	else:
		# Reviving someone: only a DOWNED team-mate, and only one close
		# enough that it is actually me doing it.
		var my_team := int(Game.roster.get(me, {}).get("team", -1))
		for rid: String in world.revive_progress.keys():
			if not world.client_downed.has(rid):
				continue
			if int(Game.roster.get(rid, {}).get("team", -2)) != my_team:
				continue
			var mate: Player = null
			for child in world.players.get_children():
				if child is Player and child.player_id == rid:
					mate = child
					break
			if mate == null \
					or mate.position.distance_to(player.position) > WorldNode.REVIVE_RADIUS + 1.0:
				continue
			var frac := float(world.revive_progress[rid])
			if frac > best:
				best = frac
				found = true
	_revive_ring.visible = found and not _menu.visible
	if found:
		_revive_ring.progress = best
		_revive_ring.queue_redraw()

## The two corner signposts saying which key opens which menu. They are
## for somebody who has not opened one yet: once either menu is up they
## are answered, and the menu itself says the rest.
func _refresh_menu_hints() -> void:
	var menus_shut: bool = not _menu.visible \
		and not (Game.world_menu != null and Game.world_menu.visible)
	if _menu_tab_left != null:
		_menu_tab_left.visible = menus_shut
	if _menu_tab_right != null:
		_menu_tab_right.visible = menus_shut


## The status strip under the hotbar: what you are holding, the time, and
## how many people are in the world.
##
## The held item's NAME is the point of it. Eight icons drawn in the same
## flat style are genuinely hard to tell apart — a Freeze Ray and a Block
## Sucker are both a small pale thing — and until now the game never said
## in words what was in your hand.
func _update_clock() -> void:
	if world == null:
		return
	var hour := int(fposmod(world.clock * 24.0, 24.0))
	var night: bool = world.clock > 0.78 or world.clock < 0.22
	if _selected_label != null:
		var parts: Array = []
		var holding := _held_name()
		if not holding.is_empty():
			parts.append(holding)
		parts.append("%s %02d:00" % ["☾" if night else "☀", hour])
		# People, then computer players. The same reason the first screen
		# splits them: "6 playing" in a room with one child and five bots
		# is the wrong answer to the only question being asked.
		var humans := 0
		var bots := 0
		for rid: String in Game.roster:
			if bool(Game.roster[rid].get("bot", false)):
				bots += 1
			else:
				humans += 1
		parts.append("%d playing" % humans if bots == 0
			else "%d playing + %d 🤖" % [humans, bots])
		_selected_label.text = "   ·   ".join(parts)

## What the player is holding, in words. Empty if their hand is empty.
func _held_name() -> String:
	var me := _player()
	if me == null:
		return ""
	var item: Dictionary = me.held()
	match str(item.kind):
		"weapon":
			return str(Weapons.spec(int(item.id)).get("name", ""))
		"block":
			return str(Blocks.info(int(item.id)).get("name", ""))
		"structure":
			return str(Structures.spec(int(item.id)).get("name", ""))
		"vehicle":
			return "Boat" if int(item.id) == VehicleGeom.KIND_BOAT else "Car"
		_:
			return ""


## THE FLAG STENCIL, shared by the icon and by its own outline so the two
## can never drift apart. Returns 0 for nothing, 1 for the pole, 2 for the
## pennant — the pennant is the bit that carries the team colour.
##
## Same shape the big map draws (`_map_flag`), so a flag looks like a flag
## wherever you meet one.
static func _flag_ink(dx: int, dy: int) -> int:
	if dx == 0 and dy >= -7 and dy <= 3:
		return 1
	if dy >= -6 and dy <= -2 and dx >= 1 and dx <= 6 - absi(dy + 4) * 2:
		return 2
	return 0






var _team_box: VBoxContainer

var _lobby_countdown: Label

var _battle_start: Button
var _add_bot_btn: Button
var _center_note: Label
var _score_label: Label
var _team_panel: VBoxContainer
var _feed_box: VBoxContainer
var _left_column: VBoxContainer
## How long a knockout stays on the feed.
const FEED_SECONDS := 10.0
var _fade: ColorRect
var _menu_tab_left: Control
var _menu_tab_right: Control
var _ctf_panel: VBoxContainer
var _ctf_panel_sig := ""
var _revive_hint: Label
var _damage_flash: ColorRect
var _vignette: TextureRect
var _damage_arrow: Label
var _damage_t := 0.0
var _damage_from := Vector3.ZERO
var _prev_hp := 8

## Battle lobby lives in the menu now: when a match opens, EVERYONE's menu
## pops open on the Game tab so each player can pick a team with their own
## controls.
func _on_match_changed() -> void:
	var player := _player()
	if player == null or world == null:
		return
	_refresh_identity()
	if world.match_phase == "LOBBY":
		_refresh_team_box()
	elif _menu.visible and world.match_phase == "SETUP":
		_close_menu()

## The chosen option is filled with the accent so everyone at the table
## can see the setup. A FILL, not just coloured text — the text-only
## version read as "stuck hover".
func _mark_selected(btn: Button, on: bool) -> void:
	if on:
		var sel := StyleBoxFlat.new()
		sel.bg_color = UiTheme.ACCENT
		sel.set_corner_radius_all(9)
		sel.content_margin_left = _us(14)
		sel.content_margin_right = _us(14)
		sel.content_margin_top = _us(7)
		sel.content_margin_bottom = _us(7)
		for state in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(state, sel)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			btn.add_theme_color_override(state, UiTheme.ON_ACCENT)
	else:
		for state in ["normal", "hover", "pressed"]:
			btn.remove_theme_stylebox_override(state)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			btn.remove_theme_color_override(state)

func _refresh_battle_highlights() -> void:
	if world == null:
		return
	_refresh_team_box()

## The team matrix: one row per player, one column per team. You can move
## yourself and any computer player; other humans only move themselves,
## so their rows are read-only dots.
func _refresh_team_box() -> void:
	if _team_box == null:
		return
	for child in _team_box.get_children():
		child.queue_free()
	if world == null:
		return
	if _add_bot_btn != null:
		_add_bot_btn.disabled = Game.roster.size() >= Game.MAX_PLAYERS
	var me := multiplayer.get_unique_id()
	var names: Array = world.client_team_names
	var team_count: int = maxi(names.size(), 2)
	var cell_w := _us(46) if team_count <= 8 else _us(32)
	var hscroll := ScrollContainer.new()
	hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hscroll.custom_minimum_size = Vector2(0, _us(25) * (Game.roster.size() + 2) + _us(14))
	_team_box.add_child(hscroll)
	var grid := GridContainer.new()
	grid.columns = team_count + 2
	grid.add_theme_constant_override("h_separation", _us(4))
	grid.add_theme_constant_override("v_separation", _us(4))
	hscroll.add_child(grid)
	grid.add_child(Label.new())
	for t in team_count:
		# Team header: colored name, click to rename in place.
		var head := Button.new()
		head.focus_mode = Control.FOCUS_NONE
		head.flat = true
		head.text = str(names[t]) if t < names.size() else str(t + 1)
		head.add_theme_font_size_override("font_size", _us(14))
		var head_style := StyleBoxFlat.new()
		head_style.bg_color = Color(0, 0, 0, 0)
		head_style.set_content_margin_all(_us(2))
		for head_state in ["normal", "hover", "pressed"]:
			head.add_theme_stylebox_override(head_state, head_style)
		head.add_theme_color_override("font_color", WorldNode.TEAM_COLORS[t])
		head.custom_minimum_size = Vector2(cell_w, 0)
		var team_index := t
		head.pressed.connect(func() -> void:
			_rename_team(head, team_index))
		grid.add_child(head)
	grid.add_child(Label.new())
	var ordered_ids: Array = Game.roster.keys()
	ordered_ids.sort_custom(func(a_id: String, b_id: String) -> bool:
		var a_bot := bool(Game.roster[a_id].get("bot", false))
		var b_bot := bool(Game.roster[b_id].get("bot", false))
		if a_bot != b_bot:
			return b_bot  # humans first
		return a_id < b_id)
	for id: String in ordered_ids:
		var entry: Dictionary = Game.roster[id]
		var team := int(entry.get("team", -1))
		var mine: bool = int(entry.peer) == me and int(entry.slot) == slot
		var bot: bool = bool(entry.get("bot", false))
		var name_label := Label.new()
		name_label.text = str(entry.name) + (" (you)" if mine else "") + ("  🤖" if bot else "")
		name_label.custom_minimum_size = Vector2(_us(120), 0)
		name_label.add_theme_font_size_override("font_size", _us(15))
		name_label.add_theme_color_override("font_color",
			WorldNode.TEAM_COLORS[team] if team >= 0 else Color.WHITE)
		grid.add_child(name_label)
		var target_id := id
		var target_slot := int(entry.slot)
		for t in team_count:
			if true:  # everyone can set every player's team (kids!)
				var cell_btn := Button.new()
				cell_btn.focus_mode = Control.FOCUS_NONE
				cell_btn.custom_minimum_size = Vector2(cell_w, _us(20))
				var style := StyleBoxFlat.new()
				style.bg_color = WorldNode.TEAM_COLORS[t] * (1.0 if t == team else 0.3)
				style.bg_color.a = 1.0
				style.set_corner_radius_all(6)
				if t == team:
					style.border_color = Color.WHITE
					style.set_border_width_all(2)
				for state in ["normal", "hover", "pressed"]:
					cell_btn.add_theme_stylebox_override(state, style)
				var pick_team := t
				cell_btn.pressed.connect(func() -> void:
					if mine:
						Game.set_local_team(target_slot, pick_team)
					elif Game.world != null:
						Game.world.sv_set_bot_team.rpc_id(1, target_id, pick_team)
					Sfx.play("tick", -8.0))
				grid.add_child(cell_btn)
			else:
				var dot := Label.new()
				dot.text = "●" if t == team else "·"
				dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				dot.add_theme_font_size_override("font_size", _us(18))
				dot.add_theme_color_override("font_color",
					WorldNode.TEAM_COLORS[t] if t == team else Color(1, 1, 1, 0.25))
				grid.add_child(dot)
		if bot:
			var kick := Button.new()
			kick.focus_mode = Control.FOCUS_NONE
			kick.text = "✕"
			kick.add_theme_font_size_override("font_size", _us(13))
			var kick_style := StyleBoxFlat.new()
			kick_style.bg_color = Color(0.14, 0.16, 0.23)
			kick_style.set_corner_radius_all(6)
			kick_style.set_content_margin_all(_us(3))
			for kick_state in ["normal", "hover", "pressed"]:
				kick.add_theme_stylebox_override(kick_state, kick_style)
			kick.add_theme_color_override("font_color", Color("ff6b6b"))
			kick.pressed.connect(func() -> void:
				if Game.world != null:
					Game.world.sv_remove_bot.rpc_id(1, target_id)
				Sfx.play("pop"))
			grid.add_child(kick)
		else:
			grid.add_child(Label.new())
	# Bottom row: an ✕ under each column deletes that team (its computer
	# players spread themselves over the remaining teams).
	if team_count > 2:
		grid.add_child(Label.new())
		for t in team_count:
			var del_btn := Button.new()
			del_btn.focus_mode = Control.FOCUS_NONE
			del_btn.flat = true
			del_btn.text = "✕"
			del_btn.add_theme_font_size_override("font_size", _us(14))
			del_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
			var gone := t
			del_btn.pressed.connect(func() -> void:
				if Game.world != null:
					Game.world.sv_remove_team.rpc_id(1, gone)
				Sfx.play("pop"))
			grid.add_child(del_btn)
		grid.add_child(Label.new())

## Under-radar panel: one colored row per team with its alive count.
func _refresh_team_panel() -> void:
	if _team_panel == null or world == null:
		return
	for child in _team_panel.get_children():
		child.queue_free()
	# STANDING / TEAM SIZE. The second number is how many are ON the team
	# and does not move all match, so a wiped team reads 0/6 and STAYS
	# LISTED — counting only the survivors made whole teams vanish from
	# the panel, which read as players being dropped from the game. The
	# first number is who can still shoot back: not downed, not out.
	var names: Array = world.client_team_names
	var standing: Dictionary = {}
	var sizes: Dictionary = {}
	for rid: String in Game.roster.keys():
		var rt := int(Game.roster[rid].get("team", -1))
		if rt < 0 or rt >= names.size():
			continue
		sizes[rt] = int(sizes.get(rt, 0)) + 1
		if world.alive_ids.has(rid) and not world.client_downed.has(rid):
			standing[rt] = int(standing.get(rt, 0)) + 1
	var ranked: Array = sizes.keys()
	ranked.sort_custom(func(a: int, b: int) -> bool:
		return int(standing.get(a, 0)) > int(standing.get(b, 0)))
	# TWENTY TEAMS DOES NOT FIT and used to be drawn anyway, straight off
	# the bottom of the screen. See TeamBoard.
	var px := TeamBoard.font_px(ranked.size(), 14)
	var room := size.y - _team_panel.position.y - _us(30)
	var cap := TeamBoard.row_cap(room, _us(px + 3))
	var mine := int(Game.roster.get(Game.player_id(
		multiplayer.get_unique_id(), slot), {}).get("team", -1))
	var show: Array = TeamBoard.visible_rows(ranked, mine, cap)
	for t_v: Variant in show:
		var t := int(t_v)
		var alive := int(standing.get(t, 0))
		var row_label := Label.new()
		row_label.text = "%s  %d/%d" % [str(names[t]), alive, int(sizes[t])]
		row_label.add_theme_font_size_override("font_size", _us(px))
		row_label.add_theme_color_override("font_color",
			WorldNode.TEAM_COLORS[t % WorldNode.TEAM_COLORS.size()] if alive > 0 \
			else Color(0.5, 0.5, 0.55, 0.7))
		row_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
		row_label.add_theme_constant_override("outline_size", 4)
		row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_team_panel.add_child(row_label)
	var missing := TeamBoard.hidden(ranked.size(), show.size())
	if missing > 0:
		var more := Label.new()
		more.text = "+%d more" % missing
		more.add_theme_font_size_override("font_size", _us(px))
		more.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		more.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
		more.add_theme_constant_override("outline_size", 4)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_team_panel.add_child(more)

## THE ROUND'S SCORELINE, over the knockout feed on the left.
##
## Capture the flag is played on a number and the number was nowhere on
## screen: you had to open a menu — which freezes everyone at the table —
## to find out whether you were winning. Knockouts scrolled past on the
## left the whole time and they do not decide anything in this mode.
##
## Taken, lost, and the net each team is on, in the team's own colour, with
## the target so you know how far there is to go.
func _refresh_ctf_panel() -> void:
	if _ctf_panel == null or world == null:
		return
	var on: bool = world.flag_mode() and not world.flags.is_empty()
	_ctf_panel.visible = on
	if not on:
		for stale in _ctf_panel.get_children():
			stale.queue_free()
		return
	var sig := "%s|%s|%d" % [str(world.ctf_caps), str(world.ctf_lost),
		int(world.ctf_target)]
	if sig == _ctf_panel_sig:
		return
	_ctf_panel_sig = sig
	for stale in _ctf_panel.get_children():
		stale.queue_free()
	var head := Label.new()
	# THE HEADING SAYS WHAT THE MODE IS PLAYED ON, and last flag standing
	# is not played on a target — it was reading "first to 3" in a mode
	# where reaching three of anything means nothing at all.
	head.text = "🛡  last flag standing   (took/lost)" if world.client_mode == "holdout" \
		else "⚑  first to %d   (took/lost)" % int(world.ctf_target)
	head.add_theme_font_size_override("font_size", _us(12))
	head.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	head.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	head.add_theme_constant_override("outline_size", 4)
	_ctf_panel.add_child(head)
	var order: Array = []
	for t in int(world.team_count):
		order.append(t)
	order.sort_custom(func(a: int, b: int) -> bool:
		return int(world.ctf_scores.get(a, 0)) > int(world.ctf_scores.get(b, 0)))
	# TWENTY TEAMS OF FIVE. Every row carried a 30px score, so twenty of
	# them was six hundred pixels of scoreboard down the side of the
	# screen and you could not see the game behind it. The score is still
	# the big number — it is what you glance at mid-fight — it is just
	# sized for how many of them there are now. See TeamBoard.
	var px := TeamBoard.font_px(order.size(), 30)
	var name_px := TeamBoard.font_px(order.size(), 15)
	var note_px := TeamBoard.font_px(order.size(), 16)
	var cap := TeamBoard.row_cap(size.y * 0.45, _us(px + 4))
	var mine := int(Game.roster.get(Game.player_id(
		multiplayer.get_unique_id(), slot), {}).get("team", -1))
	var show: Array = TeamBoard.visible_rows(order, mine, cap)
	for t_v: Variant in show:
		var t := int(t_v)
		# NAME, SCORE, then took/lost small and in brackets. It used to
		# read "Red 1 took · 0 lost · 1", which is three numbers and two
		# words for one line of a scoreboard you glance at mid-fight. The
		# score is the thing; the other two are the detail behind it, so
		# they are smaller, dimmer and out of the way.
		var line := RichTextLabel.new()
		line.bbcode_enabled = true
		line.fit_content = true
		line.scroll_active = false
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.custom_minimum_size = Vector2(_us(200), 0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# BOTH sizes, and the bold one is why this kept coming out wrong.
		# `[b]` does not draw with the normal font — it draws with the BOLD
		# font, which has its own `bold_font_size`. Overriding only
		# `normal_font_size` left the score at the theme default while the
		# bracket beside it, which carries an explicit tag, rendered
		# larger: a tiny score and a big (2/0), which is precisely
		# backwards, and has now been reported twice.
		line.add_theme_font_size_override("normal_font_size", _us(name_px))
		line.add_theme_font_size_override("bold_font_size", _us(px))
		line.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
		line.add_theme_constant_override("outline_size", 4)
		var tint: Color = WorldNode.TEAM_COLORS[t] \
			if t < WorldNode.TEAM_COLORS.size() else Color.WHITE
		# Every size stated outright rather than inherited, so nothing can
		# fall back to a theme default again.
		line.text = ("[color=#%s][font_size=%d]%s[/font_size]  "
			+ "[font_size=%d][b]%d[/b][/font_size][/color]  "
			+ "[color=#8d97ab][font_size=%d](%d/%d)[/font_size][/color]") % [
			tint.to_html(false), _us(name_px),
			str(world.client_team_names[t]) \
				if t < world.client_team_names.size() else "Team %d" % (t + 1),
			_us(px), int(world.ctf_scores.get(t, 0)), _us(note_px),
			int(world.ctf_caps.get(t, 0)), int(world.ctf_lost.get(t, 0))]
		_ctf_panel.add_child(line)
	var missing := TeamBoard.hidden(order.size(), show.size())
	if missing > 0:
		var more := Label.new()
		more.text = "+%d more — open the menu for the full table" % missing
		more.add_theme_font_size_override("font_size", _us(name_px))
		more.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		more.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
		more.add_theme_constant_override("outline_size", 4)
		_ctf_panel.add_child(more)

## Swap a team header button for a LineEdit; commit renames server-side.
func _rename_team(head: Button, index: int) -> void:
	var edit := LineEdit.new()
	edit.text = head.text
	edit.max_length = 10
	edit.add_theme_font_size_override("font_size", _us(15))
	edit.custom_minimum_size = Vector2(_us(70), 0)
	head.add_sibling(edit)
	head.visible = false
	edit.grab_focus()
	edit.select_all()
	var commit := func() -> void:
		if Game.world != null and not edit.text.strip_edges().is_empty():
			Game.world.sv_rename_team.rpc_id(1, index, edit.text)
		edit.queue_free()
		head.visible = true
	edit.text_submitted.connect(func(_t: String) -> void: commit.call())
	edit.focus_exited.connect(commit)

## A controls cheat-sheet so nobody has to memorize the pad layout.
func _build_help_tab() -> void:
	var tab := _scrolled_tab("Help", _video_tabs)
	tab.add_theme_constant_override("separation", _us(6))
	_add_section(tab, "🎮  CONTROLLER")
	for line in ["Left stick — move      L3 (click stick) — creep quietly",
			"Right stick — orbit the camera, up and down too",
			"Ⓐ — jump / select      Ⓑ or RB — dig",
			"RT — fire / place      LB — fly up      LT — descend",
			"D-pad up/down — zoom      D-pad left/right — weapon",
			"Ⓨ — camera view (orbit / top-down / first person)",
			"Start or Ⓧ — menu      in menu: LB/RB pages, LT/RT groups",
			"Hold Ⓑ — leave the game"]:
		var pad_line := Label.new()
		pad_line.text = str(line)
		pad_line.add_theme_font_size_override("font_size", _us(17))
		tab.add_child(pad_line)
	_add_section(tab, "⌨  KEYBOARD + MOUSE")
	for line in ["WASD — move      Shift — creep      Space — jump",
			"Z / X — spin camera      E — blocks      ` — menu",
			"Click — dig      Right-click — place      1-8 — hotbar",
			"T — camera view      F — fly (when idle)"]:
		var key_line := Label.new()
		key_line.text = str(line)
		key_line.add_theme_font_size_override("font_size", _us(17))
		tab.add_child(key_line)
	_add_section(tab, "🏆  BATTLE ROYALE")
	for line in ["Set up teams and computer players on Game ▸ Players.",
			"Grab crates for weapons — the sword alone won't win it.",
			"Stay inside the storm circle (watch the radar ring).",
			"Downed teammates revive if you stand close to them.",
			"Winner sticks around — battles loop until the host stops them."]:
		var tip_line := Label.new()
		tip_line.text = "• " + str(line)
		tip_line.add_theme_font_size_override("font_size", _us(17))
		tab.add_child(tip_line)

## Its own tab: every video setting individually — numbers get sliders,
## switches get checkboxes. No presets, no magic.
func _build_video_tab() -> void:
	var tab := _scrolled_tab("Video", _video_tabs)
	tab.add_theme_constant_override("separation", _us(10))
	_add_video_slider(tab, "Draw distance", "dist_blocks", 32, 208, 16, "%d blocks (16 per chunk)")
	_add_video_slider(tab, "3D resolution", "render_scale", 1, 100, 1, "%d%%")
	_add_video_slider(tab, "Shadow quality", "shadow_quality", 0, 2, 1, "%d")
	for spec in [["shadows", "Shadows"], ["ssao", "Contact shading (SSAO)"],
			["glow", "Glow"], ["lights", "Dynamic lights"],
			["water_shine", "Shiny water (sun glints)"],
			["ao", "Corner shading on blocks"], ["wire", "Wireframe"]]:
		var key := str(spec[0])
		var tbtn := Button.new()
		tbtn.focus_mode = Control.FOCUS_NONE
		tbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tbtn.add_theme_font_size_override("font_size", _us(20))
		tbtn.text = ("☑  " if Game.video[key] else "☐  ") + str(spec[1])
		var label_text := str(spec[1])
		# Every row is the same width; ON shows as a gold wash so width
		# never reads as the "selected" signal.
		var on_style := StyleBoxFlat.new()
		on_style.bg_color = Color(1.0, 0.82, 0.4, 0.18)
		on_style.set_corner_radius_all(9)
		on_style.set_content_margin_all(_us(7))
		on_style.content_margin_left = _us(14)
		on_style.content_margin_right = _us(14)
		var off_style := StyleBoxFlat.new()
		off_style.bg_color = Color(1, 1, 1, 0.05)
		off_style.set_corner_radius_all(9)
		off_style.set_content_margin_all(_us(7))
		off_style.content_margin_left = _us(14)
		off_style.content_margin_right = _us(14)
		var apply_style := func() -> void:
			var sb: StyleBoxFlat = on_style if Game.video[key] else off_style
			for st in ["normal", "hover", "pressed"]:
				tbtn.add_theme_stylebox_override(st, sb)
		apply_style.call()
		tbtn.pressed.connect(func() -> void:
			Game.video[key] = not bool(Game.video[key])
			tbtn.text = ("☑  " if Game.video[key] else "☐  ") + label_text
			apply_style.call()
			Game.video_changed.emit()
			Sfx.play("tick", -10.0))
		tab.add_child(tbtn)

func _add_video_slider(tab: Control, label_text: String, key: String,
		minv: int, maxv: int, step: int, suffix: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _us(10))
	tab.add_child(row)
	var name_label := Label.new()
	name_label.text = label_text + ":"
	name_label.custom_minimum_size = Vector2(_us(190), 0)
	name_label.add_theme_font_size_override("font_size", _us(20))
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = int(Game.video.get(key, minv))
	slider.custom_minimum_size = Vector2(_us(230), _us(24))
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = suffix % int(slider.value)
	value_label.add_theme_font_size_override("font_size", _us(20))
	row.add_child(value_label)
	slider.value_changed.connect(func(val: float) -> void:
		Game.video[key] = int(val)
		value_label.text = suffix % int(val)
		Game.video_changed.emit())

func _close_menu() -> void:
	_menu.visible = false
	_menu_dim.visible = false
	_set_nav_focus(null)
	_prev_nav_select = true
	var player := _player()
	if player != null:
		player.ui_locked = false

func _on_picked(entry: Dictionary) -> void:
	var player := _player()
	if player == null:
		return
	var target_slot := player.selected_slot
	# Never silently overwrite a collected WEAPON with a block when an
	# empty or block slot exists elsewhere — losing your Big Shooter to
	# a dirt block hurt too much.
	if entry.kind != "weapon" and player.slots[target_slot].kind == "weapon":
		for i in 8:
			if player.slots[i].kind != "weapon":
				target_slot = i
				break
	player.slots[target_slot] = {"kind": entry.kind, "id": entry.id}
	player.selected_slot = target_slot
	_slots_dirty = true

func _entry() -> Dictionary:
	return Game.roster.get(Game.player_id(multiplayer.get_unique_id(), slot), {})

func _player() -> Player:
	if world == null or world.players == null:
		return null
	for child in world.players.get_children():
		if child is Player and child.is_local and child.slot == slot:
			return child
	return null

func _refresh_identity() -> void:
	_refresh_team_box()
	var entry := _entry()
	if entry.is_empty():
		return
	_name_label.text = str(entry.name)
	if _name_chip != null:
		_name_chip.text = str(entry.name)
		var chip_team := int(entry.get("team", -1))
		_name_chip.add_theme_color_override("font_color",
			WorldNode.TEAM_COLORS[chip_team] if chip_team >= 0 else Color.WHITE)
	var my_who := str(AvatarFactory.normalize_style(entry.get("style")).get("who", ""))
	for who_key: String in _char_buttons:
		_mark_character(_char_buttons[who_key] as Button, who_key == my_who)
	if _menu_who != null:
		_menu_who.text = "%s — blocks, kits and who you are" % str(entry.name)
	if _menu != null and _menu.visible and _current_page() == PAGE_CHARACTER:
		_refresh_preview()
	var team := int(entry.get("team", -1))
	_name_label.add_theme_color_override("font_color",
		WorldNode.TEAM_COLORS[team] if team >= 0 else Color.WHITE)
	_treasure_label.text = ""
	var id := Game.player_id(multiplayer.get_unique_id(), slot)
	var hearts_on: bool = world != null and (world.survival_active \
		or world.client_mode == "battle" \
		or world.match_phase in ["SETUP", "BATTLE"])
	var hp: int = int(world.hearts.get(id, 8)) if world != null else 8
	for i in _heart_cells.size():
		(_heart_cells[i] as Label).modulate.a = 0.0 if not hearts_on \
			else (1.0 if i < hp else 0.18)

func _edit_name() -> void:
	var entry := _entry()
	if entry.is_empty():
		return
	var edit := LineEdit.new()
	edit.text = str(entry.name)
	edit.max_length = 12
	edit.add_theme_font_size_override("font_size", _us(18))
	edit.custom_minimum_size = Vector2(120, 0)
	var parent := _name_label.get_parent()
	parent.add_child(edit)
	parent.move_child(edit, _name_label.get_index())
	_name_label.visible = false
	edit.grab_focus()
	edit.select_all()
	var commit := func() -> void:
		if is_instance_valid(edit):
			Game.set_local_name(slot, edit.text)
			edit.queue_free()
			_name_label.visible = true
	edit.text_submitted.connect(func(_text: String) -> void: commit.call())
	edit.focus_exited.connect(commit)

func _process(delta: float) -> void:
	var player := _player()
	if player == null:
		return
	_poll_input(player, Game.local_inputs.get(slot), delta)
	_poll_autotest(player)
	_refresh_battle_prompts(player)
	_refresh_notices(player, delta)
	_refresh_scoreline(player, delta)
	_refresh_crosshair_and_layout(player)
	_refresh_tints(player)
	_refresh_menu_hints()
	_refresh_hotbar_icons(player)

## This seat's own input: menu keys, picker, page navigation.
##
## E opens straight onto the Blocks tab and Esc/Start onto the guide;
## either closes it again.
func _poll_input(player: Player, input: InputSlot, delta: float) -> void:
	if input != null:
		var picker_pressed := input.is_picker_pressed()
		if picker_pressed and not _prev_picker:
			_toggle_menu(player, 0)
		_prev_picker = picker_pressed
		var menu_pressed := input.is_menu_pressed()
		if menu_pressed and not _prev_menu:
			_toggle_menu(player, 0)
		_prev_menu = menu_pressed
		if _menu.visible:
			# Controller-first: bumpers change tabs, stick/D-pad moves the
			# grid, A picks (then hops to the next slot), 1-8 jump slots,
			# and view/menu buttons close.
			var pick := input.slot_pick()
			if pick != _prev_slot_pick_menu and pick >= 0:
				if pick < 8:
					player.selected_slot = pick
				else:
					player.selected_slot = posmod(
						player.selected_slot + (1 if pick == 11 else -1), 8)
				_slots_dirty = true
				Sfx.play("tick", -10.0)
			_prev_slot_pick_menu = pick
			var tab_cycle := input.tab_cycle_direction()
			if tab_cycle != 0 and not _menu_tab_latch:
				var next_tab := _current_page()
				for attempt in _PAGES.size() - 1:
					next_tab = posmod(next_tab + tab_cycle, _PAGES.size())
					if not _page_disabled(next_tab):
						break
				_set_page(next_tab)
				Sfx.play("tick", -12.0)
			_menu_tab_latch = tab_cycle != 0
			if input.is_view_toggle_pressed():
				_close_menu()
			var page := _current_page()
			if page < _pickers.size():
				_pickers[page].poll(input, delta)
			elif page == PAGE_CHARACTER:
				_poll_character_nav(input, delta)
			elif page == PAGE_MAP:
				map._poll_map_nav(input, delta)
			elif page == PAGE_SCORES:
				_refresh_scores_tab()
			else:
				_poll_page_nav(input, delta)

## The WORLD_AUTOTEST_* hooks that drive the menus with synthetic input.
func _poll_autotest(player: Player) -> void:
	if not _menu.visible and player.ui_locked:
		player.ui_locked = false
	if OS.get_environment("WORLD_AUTOTEST_PICK") != "" and slot == 0 \
			and not _autopicked and Time.get_ticks_msec() > 12000:
		_autopicked = true
		if OS.get_environment("WORLD_AUTOTEST_NAME") != "":
			Game.set_local_name(slot, OS.get_environment("WORLD_AUTOTEST_NAME"))
		var target_btn: Button = _char_buttons.get(
			OS.get_environment("WORLD_AUTOTEST_PICK"))
		if target_btn != null:
			var vp_size := get_viewport().get_visible_rect().size
			var win_size := Vector2(DisplayServer.window_get_size())
			var pt := target_btn.get_global_rect().get_center() \
				* (win_size / vp_size)
			print("AUTOPICK clicking at ", pt, " visible=", target_btn.is_visible_in_tree(),
				" vp=", get_viewport().get_visible_rect().size,
				" win=", DisplayServer.window_get_size(),
				" hud=", size, " menu_scale=", _menu.scale)
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			down.position = pt
			down.global_position = pt
			Input.parse_input_event(down)
			var up := InputEventMouseButton.new()
			up.button_index = MOUSE_BUTTON_LEFT
			up.pressed = false
			up.position = pt
			up.global_position = pt
			Input.parse_input_event(up)
	if _autopicked and not _autopick_checked and Time.get_ticks_msec() > 15000:
		_autopick_checked = true
		var my_e := _entry()
		print("AUTOPICK roster style now: ", my_e.get("style"))
	if OS.get_environment("WORLD_AUTOTEST_MENU") == "1" and slot == 0 \
			and not _autoopened and Time.get_ticks_msec() > 9000:
		_autoopened = true
		# OPEN, not toggle: a stray key press before the 9-second mark
		# would leave the menu already up, and a toggle then closed the
		# very thing the screenshot run exists to photograph.
		if not _menu.visible:
			_toggle_menu(player, 1)
	if _autoopened and _menu.visible and not OS.get_environment("WORLD_AUTOTEST_TAB").is_empty():
		_set_page(int(OS.get_environment("WORLD_AUTOTEST_TAB")))


## The prompts around a round: the start button, the lobby countdown,
## and the pick-a-team-mate-up hint.
func _refresh_battle_prompts(player: Player) -> void:
	if _game_tabs != null and _game_tabs.get_tab_count() >= 3:
		_game_tabs.set_tab_hidden(0, false)
		_game_tabs.set_tab_hidden(1, false)
	if _battle_start != null and world != null:
		_battle_start.visible = world.client_mode == "battle"
		match world.match_phase:
			"IDLE":
				_battle_start.disabled = false
				_battle_start.text = "🏆  Start Battle"
			"LOBBY":
				_battle_start.disabled = true
				_battle_start.text = "⚔  Battle starts in %d…" % int(ceil(world.match_seconds))
			"COUNTDOWN":
				_battle_start.disabled = true
				_battle_start.text = "🏆  Next battle in %d…" % int(ceil(world.match_seconds))
			_:
				_battle_start.disabled = true
				_battle_start.text = "⚔  Battle in progress"
	if _lobby_countdown != null and world != null:
		var in_lobby: bool = world.match_phase == "LOBBY"
		_lobby_countdown.visible = in_lobby
		if in_lobby:
			_lobby_countdown.text = "🏆  Battle starts in %d — pick your team!" \
				% int(ceil(world.match_seconds))
	if _revive_hint != null and world != null:
		var mate_down := ""
		# In reach of the revive itself, or still closing on them? This
		# prompt used to appear at 6 blocks and say "stay close" the whole
		# time, while the revive needs 3 — so it read as broken: you did
		# exactly what it told you to and nothing ever happened.
		var mate_reach := false
		if world.match_phase == "BATTLE":
			var my_team := int(Game.roster.get(Game.player_id(
				multiplayer.get_unique_id(), slot), {}).get("team", -1))
			var mate_near := INF
			for down_id: String in world.client_downed.keys():
				if int(Game.roster.get(down_id, {}).get("team", -2)) != my_team:
					continue
				for child in world.players.get_children():
					if child is Player and child.player_id == down_id:
						var gap: float = child.position.distance_to(player.position)
						if gap < 9.0 and gap < mate_near:
							mate_near = gap
							mate_down = str(Game.roster.get(down_id, {}).get("name", "?"))
							mate_reach = gap < WorldNode.REVIVE_RADIUS
		if not mate_down.is_empty():
			_revive_hint.visible = true
			_revive_hint.text = ("⛑  Hold still — picking %s up!" % mate_down) \
				if mate_reach else ("⛑  Get to %s to pick them up!" % mate_down)
		else:
			_revive_hint.visible = false
	_update_revive_ring(player)

## Something happened to the WORLD — the map was replaced, you rejoined —
## said in the same corner the match clock uses.
##
## It used to be a lit card in the middle of the screen, over the game, for
## every one of these. That is the right weight for "you left the game" and
## far too much for "here is a new map": it covers what a player is looking
## at to tell them something they can see for themselves.
func news(text: String, seconds := 5.0) -> void:
	_news = text
	_news_t = seconds

## The centre note, the storm countdown and the death card.
func _refresh_notices(player: Player, delta: float) -> void:
	if _center_note != null and world != null:
		var secs := int(ceil(world.match_seconds))
		var say := ""
		if world.match_phase == "LOBBY" and not _menu.visible:
			say = ("🏆  Next battle in %d" % secs) if secs > 0 \
				else "🏆  Battle starting…"
		elif world.match_phase == "BATTLE" and str(world.client_mode) == "holdout":
			# THE ROUND CLOCK. Last flag standing has no storm closing in
			# to tell you how long is left, and "how long do I have to
			# hold this" is the question the whole mode is about.
			var left := int(ceil(world.match_seconds))
			say = "🛡  %d:%02d" % [left / 60, left % 60]
		elif world.match_phase == "BATTLE" and not world.alive_ids.has(
				Game.player_id(multiplayer.get_unique_id(), slot)) \
				and not world.out_ids.has(
				Game.player_id(multiplayer.get_unique_id(), slot)):
			say = "🏆  In the next one!"
		# News wins the corner while it lasts. It is a one-off — the map
		# was replaced, you rejoined — and the clock will still be there
		# in five seconds' time.
		_news_t = maxf(0.0, _news_t - delta)
		if _news_t > 0.0 and not _news.is_empty():
			say = _news
		elif _news_t <= 0.0:
			_news = ""
		_center_note.text = say
		var showing := not say.is_empty() and not _menu.visible
		_center_note.visible = showing
		if _note_card != null:
			_note_card.visible = showing
	if _storm_label != null and world != null:
		var storm_on: bool = world.match_phase == "BATTLE" and world.storm_radius > 0.0
		# Silent until the storm is actually live — then a real countdown
		# to its minimum size (the storm bottoms out when the timer does).
		_storm_label.visible = storm_on
		if storm_on:
			var storm_secs := int(ceil(world.match_seconds))
			_storm_label.text = ("⛈  STORM!  %d" % storm_secs) if storm_secs > 0 \
				else "⛈  STORM!"
	if _death_note != null and world != null:
		var my_pid := Game.player_id(multiplayer.get_unique_id(), slot)
		var down_now: bool = bool(world.client_downed.get(my_pid, false))
		var out_now: bool = world.out_ids.has(my_pid)
		if (down_now and not _was_down) or (out_now and not _was_out):
			_death_t = 2.6
			_death_note.text = "💀  KNOCKED OUT!" if out_now \
				else "⛑  DOWNED — a teammate can revive you!"
		_was_down = down_now
		_was_out = out_now
		# WHOLE TEAM OUT? Then you are gone from the world entirely —
		# lifted clear, body hidden, watching from above. While even one
		# team-mate is still in it you stay down among them as a roaming
		# out, which is the point of being able to talk each other onto
		# a spot.
		if out_now and not _team_gone_lifted:
			var my_team := int(Game.roster.get(my_pid, {}).get("team", -2))
			var mate_left := false
			for rid: String in Game.roster.keys():
				if rid != my_pid and int(Game.roster[rid].get("team", -2)) == my_team \
						and world.alive_ids.has(rid):
					mate_left = true
					break
			if not mate_left:
				_team_gone_lifted = true
				# ASK, do not teleport. A jump straight to the spectator
				# height landed on the same frame the ten-block knockout
				# drift started, so the drift ran perfectly and was never
				# seen — see Player.lift_clear_to.
				player.lift_clear_to(float(WorldGen.CHUNK_H) - 26.0)
				player.visible = false
		elif not out_now:
			_team_gone_lifted = false
			if not player.visible:
				player.visible = true
		_death_t = maxf(0.0, _death_t - delta)
		_death_note.visible = _death_t > 0.0
		_drain_colour(down_now or out_now, delta)

## Out of the fight, so the fight stops looking like something you are in.
##
## Both states, not just elimination: DOWNED is the one people spend time
## in, and it is the one that looked like nothing more than a bad moment.
## Eased rather than switched, because a hard cut to grey reads as the
## renderer breaking, and eased back the same way for a revive — which is
## the colour rushing back in, and worth having.
func _drain_colour(out_of_it: bool, delta: float) -> void:
	if _grey == null:
		return
	var want := 1.0 if out_of_it else 0.0
	if is_equal_approx(_grey_amount, want):
		# Nothing to do, and the pass is skipped entirely while you are
		# playing — this shader reads the whole screen back, so it should
		# not be running for anybody who is still in the game.
		_grey.visible = _grey_amount > 0.001
		return
	_grey_amount = move_toward(_grey_amount, want, delta * 1.6)
	_grey.visible = _grey_amount > 0.001
	(_grey.material as ShaderMaterial).set_shader_parameter("amount", _grey_amount)
	_keep_home_in_colour()

## YOUR OWN BASE KEEPS ITS COLOUR while the rest of the world loses it.
##
## Being knocked out in capture the flag takes away the one thing you then
## most need: which of five identical grey mounds is yours to get back to.
## The team colours were the only way to tell them apart and the drain
## removes exactly those. So the patch of screen your own base is standing
## in stays in colour, and the drain becomes a signpost rather than only a
## mood.
##
## Off screen, behind you, or not playing capture the flag: no patch. A
## circle of colour in the corner pointing at nothing is worse than none.
func _keep_home_in_colour() -> void:
	var mat := _grey.material as ShaderMaterial
	var radius := 0.0
	var at := Vector2(-1.0, -1.0)
	if cam != null and world != null and world.flag_mode() \
			and _grey_amount > 0.001:
		var me := Game.player_id(multiplayer.get_unique_id(), slot)
		var mine := int(Game.roster.get(me, {}).get("team", -1))
		for entry: Array in world.flags:
			if int(entry[0]) != mine:
				continue
			var home: Vector3 = entry[1]
			# is_position_behind covers the case that matters: standing
			# with your back to your own base, where unproject_position
			# happily returns a point on screen and it is the wrong one.
			if cam.is_position_behind(home):
				break
			var screen := cam.unproject_position(home + Vector3(0, 2.0, 0))
			var view := cam.get_viewport().get_visible_rect().size
			if view.x <= 0.0 or view.y <= 0.0:
				break
			at = Vector2(screen.x / view.x, screen.y / view.y)
			if at.x < -0.2 or at.x > 1.2 or at.y < -0.2 or at.y > 1.2:
				at = Vector2(-1.0, -1.0)
				break
			radius = 0.16
			mat.set_shader_parameter("aspect", view.x / view.y)
			break
	mat.set_shader_parameter("home_at", at)
	mat.set_shader_parameter("home_radius", radius)

## The team panel, the scoreline, the low-health vignette and the
## damage flash.
func _refresh_scoreline(player: Player, delta: float) -> void:
	if _team_panel != null and world != null:
		_team_panel.visible = world.match_phase == "BATTLE"
	if _score_label != null and world != null:
		var in_battle: bool = world.match_phase == "BATTLE"
		_score_label.visible = in_battle
		if in_battle:
			var me_id := Game.player_id(multiplayer.get_unique_id(), slot)
			var team := int(Game.roster.get(me_id, {}).get("team", -1))
			# "alive out of still in the game". Downed players ARE still in
			# the game — someone can pick them up — so they count in the
			# total but not as alive. Anyone eliminated or gone is dropped
			# from both, so a team of four that loses one reads 2/3, not
			# 2/4: the number tells you how many you'd have to drop to
			# finish the team off.
			# ONE definition of "alive", used here and on the team panel:
			# standing means still in the match AND not downed. Your team's
			# second number is the SIZE OF THE TEAM, and "players left"
			# counts standing players everywhere.
			#
			# These used to measure three different things — your team's
			# survivors, your team's still-in, and the whole match's
			# still-in — so the panel could show seven while the line said
			# thirteen, with nothing on screen explaining the difference.
			var mates_alive := 0
			var mates_total := 0
			var standing := 0
			for rid: String in Game.roster.keys():
				var up: bool = world.alive_ids.has(rid) \
					and not world.client_downed.has(rid)
				if up:
					standing += 1
				if int(Game.roster[rid].get("team", -2)) != team:
					continue
				mates_total += 1
				if up:
					mates_alive += 1
			var team_name := "?"
			if team >= 0 and team < world.client_team_names.size():
				team_name = str(world.client_team_names[team])
			# The flag glyph is always red, so tint the whole label to the
			# team's colour — a red flag over "Blue" told you nothing.
			if team >= 0 and team < WorldNode.TEAM_COLORS.size():
				_score_label.add_theme_color_override("font_color",
					WorldNode.TEAM_COLORS[team])
			_score_label.text = "%s  %d/%d alive   ·   %d still standing" % [
				team_name, mates_alive, mates_total, standing]
	if _vignette != null and world != null:
		# The hurt vignette: strongest when hearts are low, eases back as
		# regen tops you up.
		#
		# NOT WHILE YOU ARE DOWN. It is driven off hearts alone, and a
		# knocked-out player has none — so it sat at full strength for the
		# entire time you were out, which is a dark red ring around the
		# screen exactly where the MAP is. That is the one thing somebody
		# who is out actually needs to read: where their own base is, and
		# which way to go to get picked up. The red wash went for this
		# reason and this is the last of it.
		#
		# There is nothing lost by hiding it. The vignette means "mind
		# yourself, you are nearly out" — advice that has already expired
		# by the time it was being shown, and the colour draining out of
		# the world says the rest.
		var vg_hp := int(world.hearts.get(_me(), 8))
		var vg_target := clampf((5.0 - vg_hp) / 5.0, 0.0, 0.75) \
			if world.match_phase == "BATTLE" else 0.0
		if _out_of_it():
			vg_target = 0.0
			_vignette.modulate.a = 0.0   # snapped, not eased: see _out_of_it
		_vignette.modulate.a = lerpf(_vignette.modulate.a, vg_target, 0.06)
	if _damage_flash != null:
		_damage_t = maxf(0.0, _damage_t - delta)
		if _out_of_it():
			_damage_t = 0.0
		_damage_flash.color.a = minf(_damage_t, 0.45) * 0.8
		_damage_arrow.visible = _damage_t > 0.0
		if _damage_arrow.visible:
			var to_threat := _damage_from - player.position
			var threat_angle := atan2(to_threat.x, -to_threat.z) + player.camera_yaw
			_damage_arrow.rotation = threat_angle
			_damage_arrow.pivot_offset = _damage_arrow.size / 2.0
			_damage_arrow.position = size / 2.0 - _damage_arrow.size / 2.0 \
				+ Vector2(sin(threat_angle), -cos(threat_angle)) * _us(90)

## The crosshair, and everything that has to be re-laid-out when this
## player's cell changes size.
func _refresh_crosshair_and_layout(player: Player) -> void:
	_crosshair.visible = player.fp_mode and not _menu.visible
	_crosshair.add_theme_font_size_override("font_size", _us(int(30 * (1.0 + player.fp_zoom * 0.8))))
	if size != _last_size:
		_last_size = size
		# Going fullscreen (or dragging the window) changes what a design
		# pixel is worth. A Theme is a plain resource, so re-hanging a
		# freshly built one repaints the whole menu without disturbing a
		# single node.
		var want_scale := UiTheme.scale_for(Vector2(DisplayServer.window_get_size()))
		if not is_equal_approx(want_scale, _menu_scale):
			_menu_scale = want_scale
			_menu.theme = UiTheme.build(_menu_scale)
			_menu.add_theme_stylebox_override("panel", UiTheme.panel_box(_menu_scale))
		# Bigger: a quarter of the cell's height was too small to read
		# anything off at a glance.
		var map_px := clampf(size.y * 0.32, 150.0, 460.0)
		# Hotbar chips scale with the cell so small screens aren't swamped.
		var chip_px := clampf(size.y * 0.045, 30.0, 64.0)
		for hb_frame in _chips:
			(hb_frame as Control).custom_minimum_size = Vector2(chip_px, chip_px)
			(hb_frame.get_child(1) as Label).add_theme_font_size_override(
				"font_size", maxi(9, int(chip_px * 0.24)))
		for cell in _heart_cells:
			(cell as Label).add_theme_font_size_override(
				"font_size", maxi(11, int(chip_px * 0.38)))
		_selected_label.add_theme_font_size_override(
			"font_size", maxi(11, int(chip_px * 0.3)))
		# THE MATCH CLOCK, and the biggest thing on the screen that is not
		# the game. This is where "next battle in 4" is read from across a
		# room by somebody who is not looking for it.
		#
		# It was chip_px * 0.36 — about thirteen pixels on a 1280 screen,
		# smaller than the numbers on the hotbar chips underneath it. That
		# is the whole of why it was never noticed. The size set when the
		# label is BUILT does not survive to the screen: this line runs on
		# the first layout and replaces it, so this is the only number that
		# has ever mattered.
		_center_note.add_theme_font_size_override(
			"font_size", maxi(30, int(chip_px * 1.0)))
		if _storm_label != null:
			_storm_label.add_theme_font_size_override(
				"font_size", maxi(12, int(chip_px * 0.4)))
		if _death_note != null:
			_death_note.add_theme_font_size_override(
				"font_size", maxi(20, int(chip_px * 0.85)))
		map._radar.position = Vector2(size.x - map_px - 10, 10)
		map._radar.size = Vector2(map_px, map_px)
		# The clock and player count used to sit here, under the radar, and
		# are in the status bar under the hotbar now — so the team panel
		# tucks straight up under the radar with just a gap.
		if _team_panel != null:
			_team_panel.position = Vector2(size.x - map_px - 10, 14 + map_px)
			_team_panel.custom_minimum_size = Vector2(map_px, 0)
		# Split-screen: fonts are sized for the full window, so shrink the
		# whole menu to fit this player's cell instead of spilling over.
		var win_w := float(DisplayServer.window_get_size().x)
		var cell_frac := clampf(size.x / maxf(win_w, 1.0), 0.25, 1.0)
		if cell_frac < 0.95:
			_menu.scale = Vector2.ONE * (cell_frac * 1.42)
			_menu.anchor_left = 0.02
			_menu.anchor_right = 0.98
			_menu.anchor_top = 0.04
			_menu.anchor_bottom = 0.94
		else:
			_menu.scale = Vector2.ONE
			_menu.anchor_left = 0.1
			_menu.anchor_right = 0.9
		_selected_label.add_theme_font_size_override("font_size",
			int(clampf(size.x / 45.0, 16.0, 34.0)))
		_last_index = -1

## The full-screen tints: under water, inside the storm, and the storm
## wall's own warning.
func _refresh_tints(player: Player) -> void:
	if _menu != null:
		# Scale around the middle so the shrunken menu stays centered in
		# this player's cell instead of hugging the top-left corner.
		_menu.pivot_offset = _menu.size / 2.0
	if _chip != null:
		_chip.visible = not _menu.visible and _treasure_label.text != ""
	if _water_tint != null and world != null and world.chunks != null:
		var eye := player.position + Vector3(0, Player.EYE_HEIGHT, 0)
		var under: bool = Blocks.is_liquid(world.chunks.get_block(
			Vector3i(floori(eye.x), floori(eye.y), floori(eye.z))))
		_water_tint.color.a = lerpf(_water_tint.color.a, 0.35 if under else 0.0, 0.25)
	if _storm_tint != null and world != null:
		var danger := 0.0
		if not _out_of_it() and world.match_phase == "BATTLE" \
				and world.storm_radius > 0.0 \
				and Vector2(player.position.x - world.storm_center.x,
					player.position.z - world.storm_center.z).length() > world.storm_radius:
			danger = 0.25
		_storm_tint.color.a = lerpf(_storm_tint.color.a, danger, 0.1)
	# Caught outside the storm: a big arrow home plus the distance.
	if world != null and not _out_of_it() and world.match_phase == "BATTLE" \
			and world.storm_radius > 0.0:
		var flat := Vector2(player.position.x - world.storm_center.x,
			player.position.z - world.storm_center.z)
		var outside: float = flat.length() - world.storm_radius
		if outside > 0.0:
			var to_center := -flat
			var angle := atan2(to_center.x, -to_center.y) + player.camera_yaw
			var arrows := ["⬆", "⬈", "➡", "⬊", "⬇", "⬋", "⬅", "⬉"]
			var arrow: String = arrows[posmod(int(round(angle / (PI / 4.0))), 8)]
			_storm_arrow.text = "%s  STORM! run %dm  %s" % [arrow, int(outside), arrow]
			_storm_arrow.visible = true
		else:
			_storm_arrow.visible = false
	else:
		_storm_arrow.visible = false

## The hotbar's icons, redrawn only when what is in it actually
## changes — this runs every frame.
func _refresh_hotbar_icons(player: Player) -> void:
	var held_now := str(player.held())
	# The CONTENTS of the bar, not just which slot is lit. Redrawing only on
	# a changed selection or a changed held item missed every path that
	# replaces the slots from outside — the match kit arriving over the
	# network, a crate going into an empty slot, the block sucker. The kit
	# was applied correctly and the bar simply never repainted, which looks
	# exactly like the kit never arriving: slot 0 is a Little Shooter in the
	# creative loadout AND in the capture-the-flag one, so even the held
	# item was unchanged.
	var slots_sig := ""
	for entry: Dictionary in player.slots:
		slots_sig += "%s%d," % [str(entry.kind), int(entry.id)]
	if player.selected_slot != _last_index or _slots_dirty \
			or held_now != _last_held or slots_sig != _last_slots_sig:
		_last_index = player.selected_slot
		_last_held = held_now
		_last_slots_sig = slots_sig
		_slots_dirty = false
		_selected_label.text = ""
		var slot_px := clampf(size.x / 13.0, 44.0, 96.0)
		for i in _chips.size():
			var frame: Panel = _chips[i]
			var entry: Dictionary = player.slots[i]
			var selected := i == _last_index
			frame.custom_minimum_size = Vector2(slot_px, slot_px) * (1.18 if selected else 1.0)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.08, 0.09, 0.14, 0.85)
			style.set_corner_radius_all(8)
			style.border_color = UiTheme.ACCENT if selected else Color(1, 1, 1, 0.25)
			style.set_border_width_all(4 if selected else 2)
			frame.add_theme_stylebox_override("panel", style)
			var icon: BlockIcon = frame.get_child(0)
			icon.block_id = int(entry.id)
			icon.kind = str(entry.kind)
			icon.dimmed = not selected
			icon.queue_redraw()
			if i < _menu_slot_buttons.size():
				var menu_btn: Button = _menu_slot_buttons[i]
				var menu_icon: BlockIcon = menu_btn.get_child(0)
				menu_icon.block_id = int(entry.id)
				menu_icon.kind = str(entry.kind)
				menu_icon.dimmed = not selected
				menu_icon.queue_redraw()
				menu_btn.modulate = Color(1, 1, 1, 1.0) if selected else Color(1, 1, 1, 0.6)
