class_name Main
extends Control
## Client UI shell (and server bootstrap). Two layers: the connect screen and
## the in-world screen (split-screen viewports + a thin shared overlay).
## When launched headless (or with --server / WORLD_ROLE=server) no UI is
## built at all; we just start listening.

const TITLE := "BattleBox"
const BG_TOP := Color("22304a")
const BG_BOTTOM := Color("10141f")
const GOLD := Color("ffd166")

const LEAVE_HOLD_SECONDS := 1.2

## The end-of-round card. See final_scores.gd.
var final_scores: FinalScores
var _lobby_screen: LobbyScreen
var _connect_screen: Control
var _game_screen: Control
var _world_menu: WorldMenu
## The world menu is opened for the host once, on their first join.
var _showed_opening_menu := false
var _split: SplitScreen
var _address_edit: LineEdit
var _play_button: Button
var _play_holder: Control
var _manual_hint: Label
var _status_label: Label
var _clock_label: Label
var _players_label: Label
var _survival_button: Button
var _battle_button: Button
var _lobby_panel: PanelContainer
var _lobby_label: Label
var _join_hint: Label
var _storm_tint: ColorRect
var _team_rows: VBoxContainer
var _wave_label: Label
var _banner: Label
var _banner_shown_ms := 0
var _vote_panel: PanelContainer
var _minimap: TextureRect
var _loading_label: Label

var _prev_pressed: Dictionary = {}
var _leave_hold: Dictionary = {}
var _in_world := false

# --- Connection keep-alive -----------------------------------------
## Nobody should ever have to click Connect. The client dials the default
## server the moment it launches and, if the link drops, says so and keeps
## dialling until it's back — a four-year-old can't hunt for a mouse.
const RECONNECT_DELAY := 2.0
## A WebSocket that can't reach the host sometimes just sits there instead
## of reporting a failure, so give any one attempt this long to land.
const CONNECT_TIMEOUT := 8.0
## Attempts before the address box appears for a grown-up to fix.
const ATTEMPTS_BEFORE_MANUAL := 4

var _want_url := ""
var _connecting := false
var _connect_started_ms := 0
var _retry_at_ms := 0
var _attempts := 0
## Seats to put back after a drop, so the kids don't have to re-join.
var _rejoin: Array = []

## Which room this client is in, or wants to be in. Empty until the lobby
## screen says. It survives a dropped link on purpose: a reconnect has to
## come back to the SAME game, not to whichever one is the default.
var _room_code := ""
## What that room is called, for the "reconnecting to…" line.
var _room_name := ""

func _ready() -> void:
	if _is_server_mode():
		if Net.start_server() != OK:
			get_tree().quit(1)
			return
		# What room this process is, and the watchdog that ends it when the
		# last player leaves. See room.gd — a room IS a server process.
		var room := Room.new()
		room.name = "Room"
		add_child(room)
		print(room.describe())
		Game.room = room
		Game.create_world()
		_arm_selfcheck()
		return
	# The 3D world lives in the root viewport's World3D but is only ever
	# rendered through the split-screen SubViewports (which share that world);
	# rendering it from the root too would waste a full pass and, with no
	# camera, spams fog/compute errors.
	get_viewport().disable_3d = true
	# Lets the Wireframe video toggle actually draw wireframes at runtime.
	RenderingServer.set_debug_generate_wireframes(true)
	final_scores = FinalScores.new(self)
	_build_lobby_screen()
	_build_connect_screen()
	_build_game_screen()
	Net.connected_to_server.connect(_on_connected)
	Net.connection_failed.connect(_on_connect_failed)
	Net.server_disconnected.connect(_on_server_lost)
	Game.roster_changed.connect(_on_roster_changed)
	# Kicked the last local player (the ✕ in the world menu): tear the
	# split screen down and put the join prompt back up. The connection
	# stays — this machine is still watching the world, it just has
	# nobody in it.
	Game.all_local_left.connect(func() -> void:
		if _split != null:
			_split.update_layout()
		_show_banner("You left the game — press Ⓐ or Space to join again", true))
	# A room named on the way in — a shared link, or a test harness — skips
	# the lobby entirely and goes straight to that game. Otherwise the
	# lobby is the first screen, with Play focused so that Space, Enter or
	# Ⓐ is still the whole of what anyone has to do.
	var wanted := _room_on_launch()
	if wanted.is_empty() and OS.get_environment("WORLD_AUTOCONNECT").is_empty():
		_show_screen(_lobby_screen)
		_address_edit.text = Game.server_url()
		_web_loading_done_soon()
	else:
		_room_code = wanted
		_show_screen(_connect_screen)
		_address_edit.text = Game.server_url()
		_dial()
	# WORLD_MENU_PROBE=1: drive the world menu with synthetic input.
	if OS.get_environment("WORLD_MENU_PROBE") == "1":
		add_child(load("res://tests/menu_probe.gd").new())
	_arm_selfcheck()
	# WORLD_SHOTS=<dir>: save a screenshot every 1.5s (visual debugging).
	var shots_dir := OS.get_environment("WORLD_SHOTS")
	if not shots_dir.is_empty():
		var shot_timer := Timer.new()
		shot_timer.wait_time = 1.5
		var counter := [0]
		shot_timer.timeout.connect(func() -> void:
			counter[0] += 1
			get_viewport().get_texture().get_image().save_png(
				"%s/shot_%03d.png" % [shots_dir, counter[0]]))
		add_child(shot_timer)
		shot_timer.start()

## WORLD_SELFCHECK=<seconds>: report the world state reached, then quit.
## Both roles do it, and tools/integration_test.py reads both reports.
func _arm_selfcheck() -> void:
	var seconds := SelfCheck.wanted()
	if seconds > 0.0:
		add_child(SelfCheck.new(seconds))

func _is_server_mode() -> bool:
	if OS.get_environment("WORLD_ROLE") == "client":
		return false
	return DisplayServer.get_name() == "headless" \
		or OS.get_environment("WORLD_ROLE") == "server" \
		or "--server" in OS.get_cmdline_user_args()

# ------------------------------------------------------------------
# Screens
# ------------------------------------------------------------------

## Which screen the player is looking at: "lobby" while picking a game,
## "connecting" while dialling one, "world" once in it. Reported by
## SelfCheck so a headless run can tell "could not join" apart from
## "joined and then found an empty world" — which look identical from
## outside and have nothing in common.
func current_screen() -> String:
	if _game_screen != null and _game_screen.visible:
		return "world"
	if _lobby_screen != null and _lobby_screen.visible:
		return "lobby"
	return "connecting"

func _show_screen(screen: Control) -> void:
	for child in [_lobby_screen, _connect_screen, _game_screen]:
		if child != null:
			child.visible = child == screen

static func ui_scale() -> float:
	return clampf(DisplayServer.window_get_size().x / 1100.0, 1.15, 3.0)

func _make_label(text: String, size: int, color := Color.WHITE, outline := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(size * ui_scale()))
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
		label.add_theme_constant_override("outline_size", outline)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _gradient_bg() -> TextureRect:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([BG_TOP, BG_BOTTOM])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect

## Which room this client was launched into, if any.
##
## In a browser that is `?room=<code>` on the page's own URL, which is what
## makes a private game shareable as a LINK rather than as a code somebody
## has to read out and somebody else has to type. WORLD_ROOM does the same
## for a native client and for the test harnesses.
func _room_on_launch() -> String:
	if OS.has_feature("web"):
		var found := str(JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('room') || ''", true))
		if not found.is_empty() and found != "null":
			return found.strip_edges().to_lower()
	return OS.get_environment("WORLD_ROOM").strip_edges().to_lower()

func _build_lobby_screen() -> void:
	_lobby_screen = LobbyScreen.new()
	_lobby_screen.visible = false
	_lobby_screen.add_child(_gradient_bg())
	# The gradient is added first but ends up on top; push it behind.
	_lobby_screen.move_child(_lobby_screen.get_child(_lobby_screen.get_child_count() - 1), 0)
	_lobby_screen.join_requested.connect(_join_room)
	add_child(_lobby_screen)

## Picked a game: remember it, then dial it. Everything after this is the
## same reconnect loop the client always had — it just has a room in the
## address now.
func _join_room(code: String, display_name: String) -> void:
	_room_code = code
	_room_name = display_name
	_attempts = 0
	_want_url = ""
	_show_screen(_connect_screen)
	_dial()

## Back to the lobby, because the room we were in is not there any more.
## Distinct from a dropped link, which keeps retrying the same game.
## Tell a browser's loading screen that the game is up.
##
## THE LOBBY SCREEN IS "READY". It used to be the connect handler that
## said so, because the client dialled a server the moment it launched and
## either got in or failed. The lobby connects to nothing and waits for a
## choice, so nothing said it at all: the loading video sat over a
## perfectly good screen, a press was recorded but never acted on, and the
## only way in was the 90-second failsafe.
##
## Deferred a beat so the overlay never lifts onto a canvas that has not
## drawn the lobby yet.
func _web_loading_done_soon() -> void:
	get_tree().create_timer(0.15).timeout.connect(Game.web_loading_done)

func _back_to_lobby(message: String) -> void:
	Net.go_offline()
	_connecting = false
	_retry_at_ms = 0
	_room_code = ""
	_want_url = ""
	_show_screen(_lobby_screen)
	_web_loading_done_soon()
	_lobby_screen.refresh()
	_lobby_screen.call("_set_status", message)

func _build_connect_screen() -> void:
	_connect_screen = Control.new()
	_connect_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_connect_screen.add_child(_gradient_bg())
	add_child(_connect_screen)
	# A slow drift of voxel blocks behind the title — first impressions.
	_backdrop = Control.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_screen.add_child(_backdrop)
	var drift_ids := [Blocks.GRASS, Blocks.BRICK, Blocks.GOLD, Blocks.WOOL_RED,
		Blocks.GLASS, Blocks.LEAVES, Blocks.WOOL_BLUE, Blocks.PUMPKIN,
		Blocks.DIAMOND, Blocks.WOOL_PURPLE, Blocks.SANDSTONE, Blocks.ICE,
		Blocks.LANTERN, Blocks.WOOL_TEAL]
	for i in 14:
		var cube := BlockIcon.new(drift_ids[i % drift_ids.size()])
		var px := 30 + (i * 37) % 46
		cube.size = Vector2(px, px)
		cube.position = Vector2(fmod(i * 461.7, 1.0) * 1200.0 + 20.0,
			fmod(i * 173.3, 1.0) * 700.0)
		cube.modulate = Color(1, 1, 1, 0.16 + fmod(i * 0.618, 1.0) * 0.2)
		cube.pivot_offset = cube.size / 2.0
		cube.set_meta("speed", 8.0 + fmod(i * 0.37, 1.0) * 16.0)
		cube.set_meta("spin", (fmod(i * 0.73, 1.0) - 0.5) * 0.5)
		_backdrop.add_child(cube)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_connect_screen.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	# A QUIET WORDMARK, not a title card. The name is already on the
	# loading screen in front of this one (see export_presets.cfg's
	# head_include), so a second, enormous BattleBox — shown for the
	# fraction of a second between the download finishing and the socket
	# opening — was the game introducing itself twice and delaying the
	# world to do it. This screen earns its keep on a RECONNECT, where it
	# has something to say; it does not need to shout on the way in.
	box.add_child(_make_label(TITLE, 30, GOLD, 6))
	box.add_child(_make_label("Build. Battle. Be the last one standing.",
		17, Color(1, 1, 1, 0.7)))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)
	# The address box and Play button are for a grown-up rescuing a wrong
	# address — they stay hidden while the client is dialling by itself.
	_address_edit = LineEdit.new()
	_address_edit.text = Net.default_server_url()
	_address_edit.add_theme_font_size_override("font_size", 22)
	_address_edit.custom_minimum_size = Vector2(500, 0)
	_address_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_address_edit.visible = false
	box.add_child(_address_edit)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.text = "  ▶  Play  "
	button.add_theme_font_size_override("font_size", 34)
	var play_style := StyleBoxFlat.new()
	play_style.bg_color = GOLD
	play_style.set_corner_radius_all(12)
	play_style.content_margin_left = 44
	play_style.content_margin_right = 44
	play_style.content_margin_top = 10
	play_style.content_margin_bottom = 10
	var play_hover: StyleBoxFlat = play_style.duplicate()
	play_hover.bg_color = GOLD.lightened(0.15)
	button.add_theme_stylebox_override("normal", play_style)
	button.add_theme_stylebox_override("hover", play_hover)
	button.add_theme_stylebox_override("pressed", play_hover)
	button.add_theme_color_override("font_color", Color("1c2333"))
	button.add_theme_color_override("font_hover_color", Color("1c2333"))
	button.add_theme_color_override("font_pressed_color", Color("1c2333"))
	button.pressed.connect(_on_connect_pressed)
	var holder := CenterContainer.new()
	holder.visible = false
	holder.add_child(button)
	box.add_child(holder)
	# _play_button is the container, so hiding it hides the centring too.
	_play_button = button
	_play_holder = holder
	_manual_hint = _make_label("Grown-ups: check the address above", 16,
		Color(1, 1, 1, 0.5))
	_manual_hint.visible = false
	box.add_child(_manual_hint)
	_address_edit.text_submitted.connect(func(_t: String) -> void: _on_connect_pressed())
	_status_label = _make_label("Finding the world…", 18, Color(1, 1, 1, 0.75))
	box.add_child(_status_label)

func _build_game_screen() -> void:
	_game_screen = Control.new()
	_game_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_screen.visible = false
	add_child(_game_screen)
	_split = SplitScreen.new()
	_game_screen.add_child(_split)
	_loading_label = _make_label("", 26, GOLD, 6)
	_loading_label.visible = false  # retired: it confused everyone
	_loading_label.set_anchors_preset(Control.PRESET_CENTER)
	_loading_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_screen.add_child(_loading_label)

	# Top-right cluster: the minimap with the clock and player count under
	# it, all sized from the window (rebuilt on resize).
	_minimap = TextureRect.new()
	_minimap.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Retired in favor of the per-player radar in each PlayerHud; the node
	# stays so the layout math and 3-player big map keep working.
	_minimap.visible = false
	_game_screen.add_child(_minimap)
	_clock_label = _make_label("", 20, Color.WHITE, 4)
	_clock_label.visible = false  # each PlayerHud shows its own clock now
	_game_screen.add_child(_clock_label)
	_players_label = _make_label("", 16, Color(1, 1, 1, 0.75), 4)
	_players_label.visible = false
	_game_screen.add_child(_players_label)
	_wave_label = _make_label("", 20, Color("ff6b6b"), 4)
	_game_screen.add_child(_wave_label)
	_join_hint = _make_label("🎮  New player?  Press Ⓐ on another controller to hop in!",
		15, Color(1, 1, 1, 0.65), 4)
	_join_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_join_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_join_hint.offset_top = int(-190 * ui_scale())
	_join_hint.visible = false
	_game_screen.add_child(_join_hint)
	_layout_topright()
	get_viewport().size_changed.connect(func() -> void:
		_layout_topright()
		if _split != null:
			_split.suppress_capture(1500)
			if _in_world:
				_split.update_layout())
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.85)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(int(14 * ui_scale()))
	# Reset vote panel.
	_vote_panel = PanelContainer.new()
	_vote_panel.add_theme_stylebox_override("panel", style.duplicate())
	_vote_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_vote_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_vote_panel.offset_top = 46
	_vote_panel.visible = false
	_game_screen.add_child(_vote_panel)
	var vote_row := HBoxContainer.new()
	vote_row.add_theme_constant_override("separation", 10)
	_vote_panel.add_child(vote_row)
	vote_row.add_child(_make_label("Reset the world with a NEW map?", 16, GOLD))
	var yes := Button.new()
	yes.focus_mode = Control.FOCUS_NONE
	yes.text = "Yes!"
	yes.pressed.connect(func() -> void:
		Game.world.sv_reset_answer.rpc_id(1, true)
		_vote_panel.visible = false)
	vote_row.add_child(yes)
	var no := Button.new()
	no.focus_mode = Control.FOCUS_NONE
	no.text = "No"
	no.pressed.connect(func() -> void:
		Game.world.sv_reset_answer.rpc_id(1, false)
		_vote_panel.visible = false)
	vote_row.add_child(no)
	var map_timer := Timer.new()
	map_timer.wait_time = 1.5
	map_timer.timeout.connect(_update_minimap)
	add_child(map_timer)
	map_timer.start()
	# Battle-royale lobby overlay: countdown + team picking per local player.
	_lobby_panel = PanelContainer.new()
	_lobby_panel.add_theme_stylebox_override("panel", style.duplicate())
	_lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lobby_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lobby_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lobby_panel.visible = false
	_game_screen.add_child(_lobby_panel)
	var lobby_box := VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", int(12 * ui_scale()))
	_lobby_panel.add_child(lobby_box)
	_lobby_label = _make_label("BATTLE ROYALE", 34, GOLD, 6)
	lobby_box.add_child(_lobby_label)
	lobby_box.add_child(_make_label("Pick your team!", 20, Color.WHITE))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", int(8 * ui_scale()))
	lobby_box.add_child(presets)
	presets.add_child(_make_label("Storm:", 18, Color(1, 1, 1, 0.7)))
	for minutes in [3, 5, 8]:
		var preset_btn := Button.new()
		preset_btn.focus_mode = Control.FOCUS_NONE
		preset_btn.focus_mode = Control.FOCUS_NONE
		preset_btn.text = "%d min" % minutes
		preset_btn.add_theme_font_size_override("font_size", int(18 * ui_scale()))
		var m: int = minutes
		preset_btn.pressed.connect(func() -> void:
			Game.world.sv_match_config.rpc_id(1, m, -1))
		presets.add_child(preset_btn)
	var loot_btn := Button.new()
	loot_btn.focus_mode = Control.FOCUS_NONE
	loot_btn.focus_mode = Control.FOCUS_NONE
	loot_btn.text = "Loot only"
	loot_btn.toggle_mode = true
	loot_btn.add_theme_font_size_override("font_size", int(18 * ui_scale()))
	loot_btn.toggled.connect(func(on: bool) -> void:
		Game.world.sv_match_config.rpc_id(1, -1, 1 if on else 0))
	presets.add_child(loot_btn)
	_team_rows = VBoxContainer.new()
	_team_rows.add_theme_constant_override("separation", int(8 * ui_scale()))
	lobby_box.add_child(_team_rows)
	# Storm warning tint.
	_storm_tint = ColorRect.new()
	_storm_tint.color = Color(0.9, 0.15, 0.1, 0.0)
	_storm_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_screen.add_child(_storm_tint)
	# Center banner for survival results.
	_banner = _make_label("", 40, GOLD, 8)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.visible = false
	var banner_bg := StyleBoxFlat.new()
	banner_bg.bg_color = Color(0.05, 0.06, 0.1, 0.92)
	banner_bg.set_corner_radius_all(18)
	banner_bg.set_content_margin_all(int(26 * ui_scale()))
	banner_bg.border_color = GOLD
	banner_bg.set_border_width_all(2)
	_banner.add_theme_stylebox_override("normal", banner_bg)
	_game_screen.add_child(_banner)

# ------------------------------------------------------------------
# Connection flow
# ------------------------------------------------------------------

func _on_connect_pressed() -> void:
	var url := _address_edit.text.strip_edges()
	if url.is_empty():
		return
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://" + url
	# A hand-typed address becomes the one we keep retrying, and the one
	# this machine starts on next time.
	if url != _want_url:
		_attempts = 0
		_want_url = url
		Game.set_server_url(url)
	_dial()

## Where this client should be dialling right now.
##
## WORLD_AUTOCONNECT pins a whole address and bypasses the lobby, which is
## how the integration harness talks to one room directly. Otherwise it is
## the saved server with this client's room on the end.
func _target_url() -> String:
	var forced := OS.get_environment("WORLD_AUTOCONNECT")
	if not forced.is_empty():
		return forced
	return Net.room_socket(Game.server_url(), _room_code)

## One connection attempt. _process watches it and retries on its own.
func _dial() -> void:
	if _want_url.is_empty():
		_want_url = _target_url()
	_attempts += 1
	_connecting = true
	_connect_started_ms = Time.get_ticks_msec()
	_retry_at_ms = 0
	_set_status("Finding the world…" if _attempts <= 1 else _waiting_text())
	Net.connect_to(_want_url)

func _waiting_text() -> String:
	if _attempts <= ATTEMPTS_BEFORE_MANUAL:
		return "Lost the world — reconnecting…"
	return "Lost the world — still trying (%s)" % _want_url

## Give up on this attempt and queue another.
##
## Never gives up on the always-on game — a home network comes back and
## the kids should be back in it without anyone touching anything. It DOES
## give up on a created room, because those end: retrying a code whose
## process exited an hour ago is a reconnect loop with no possible end,
## and the honest answer is to say so and offer the list again.
func _retry_soon(message: String) -> void:
	if not _room_code.is_empty() and _room_code != Room.HOUSE_CODE \
			and _attempts >= ATTEMPTS_BEFORE_MANUAL:
		var was := _room_name if not _room_name.is_empty() else _room_code
		_back_to_lobby("%s has finished — pick another game" % was)
		return
	_connecting = false
	Net.go_offline()
	_set_status(message)
	_retry_at_ms = Time.get_ticks_msec() + int(RECONNECT_DELAY * 1000.0)
	# Only once it's clearly not coming back does the grown-up UI appear.
	var manual := _attempts >= ATTEMPTS_BEFORE_MANUAL
	if _address_edit != null:
		_address_edit.visible = manual
	if _play_holder != null:
		_play_holder.visible = manual
	if _manual_hint != null:
		_manual_hint.visible = manual

func _on_connect_failed() -> void:
	# Something is wrong and the connect screen is now the useful one, so
	# lift the browser's loading screen off it. Otherwise the player
	# watches a demo reel loop while the game quietly fails behind it.
	Game.web_loading_done()
	_retry_soon(_waiting_text())

func _on_connected() -> void:
	print("Connected to world server as peer %d" % multiplayer.get_unique_id())
	_connecting = false
	_attempts = 0
	_retry_at_ms = 0
	_set_status("")
	if _address_edit != null:
		_address_edit.visible = false
	if _play_holder != null:
		_play_holder.visible = false
	if _manual_hint != null:
		_manual_hint.visible = false
	var world := Game.create_world()
	_split.world = world
	world.world_ready.connect(func() -> void:
		_loading_label.visible = false
		# Progressively pull the whole island in the background so travel
		# never waits on the server.
		for i in 4:
			var radius: int = [8, 11, 14, 17][i]
			get_tree().create_timer(2.0 + i * 5.0).timeout.connect(func() -> void:
				if Game.world != null and Game.world.chunks != null:
					Game.world.chunks.prefetch(radius)))
	# The world menu belongs to the table, not to one player: full screen,
	# keyboard and mouse only, ` to open.
	if _world_menu == null:
		_world_menu = WorldMenu.new()
		_game_screen.add_child(_world_menu)
		Game.world_menu = _world_menu
	_world_menu.world = world
	# Once only — _on_connected runs again on every reconnect.
	if not Game.video_changed.is_connected(_apply_video):
		Game.video_changed.connect(_apply_video)
	# APPLY the saved settings, don't just remember them: video.cfg was
	# loaded into Game.video at boot and shown correctly in the menu, but
	# nothing pushed it at the renderer until you toggled something — so
	# glow/SSAO/shadows you had turned OFF came back on every restart
	# (complete with the artifacts that made you turn them off).
	# Deferred once for this frame's world, then again when the sky and
	# chunk views actually exist.
	_apply_video.call_deferred()
	world.world_ready.connect(_apply_video)
	world.survival_changed.connect(_refresh_survival)
	world.match_changed.connect(_refresh_match)
	world.match_changed.connect(func() -> void:
		if Game.world == null:
			return
		# The final table belongs to the END phase and to nothing else.
		# This used to name the phases it hid FOR — LOBBY, SETUP, BATTLE —
		# and so missed the one that actually happens when a battle
		# finishes and no new one follows: END times out into IDLE when
		# the loop is off or the last human has left. The table then sat
		# there for good, with nothing on it to press.
		if not MatchUi.final_table_shows(str(Game.world.match_phase)):
			final_scores.hide_now()
		if Game.world.match_phase == "COUNTDOWN":
			_show_banner("Next battle starting soon — fresh map incoming!"))
	world.match_won.connect(func(winner: int) -> void:
		# The scoreboard says who won, how many games they have taken and
		# what everybody scored — so no banner on top of it.
		if winner >= 0:
			Sfx.play("cheer", -4.0)
		final_scores.show(winner))
	world.reset_vote_started.connect(func() -> void: _vote_panel.visible = true)
	world.reset_result.connect(func(happened: bool) -> void:
		_vote_panel.visible = false
		_show_banner("A brand new world!" if happened else "Map reset was voted down"))
	world.survival_ended.connect(func(seconds: float, bonked: int) -> void:
		_show_banner("You survived %d:%02d and bonked %d Grumps!" % [
			int(seconds / 60.0), int(seconds) % 60, bonked])
	)
	_refresh_survival()
	_in_world = true
	_loading_label.visible = false
	# The browser's loading screen has been sitting over the top of all of
	# this. THIS is the moment it has been waiting for — not the download
	# finishing, which happened a while ago.
	Game.web_loading_done()
	_show_screen(_game_screen)
	_split.update_layout()
	# Put everyone who was playing before the drop straight back in their
	# seats — nobody presses anything to resume.
	if not _rejoin.is_empty():
		var seats: Array = _rejoin
		_rejoin = []
		for input in seats:
			Game.join_local(input as InputSlot)
		_split.update_layout()
		_show_banner("Back in the world!")
	_maybe_start_autotest()

## WORLD_AUTOTEST=<n>: join n bot players who wander, dig and build — lets a
## headless client soak-test a full world session.
func _maybe_start_autotest() -> void:
	var bots := OS.get_environment("WORLD_AUTOTEST")
	if not bots.is_valid_int() or bots.to_int() <= 0:
		return
	# WORLD_AUTOTEST_HUMAN=1: the first seat is a plain keyboard slot, so
	# the roster contains a "human" (idle) — exercises the humans-only
	# paths like the battle loop's countdown.
	for i in mini(bots.to_int(), Game.MAX_LOCAL):
		if i == 0 and OS.get_environment("WORLD_AUTOTEST_HUMAN") == "1":
			Game.join_local(InputSlot.new(InputSlot.Kind.KEYBOARD_WASD))
		else:
			Game.join_local(BotSlot.new(i))
	_split.update_layout()
	# WORLD_AUTOTEST_WHO=a,f,k,...: pin each seat to a named character.
	# WORLD_AUTOTEST_PICK drives the picker UI instead, which can only
	# reach the grid when the character page happens to be on screen.
	var who_list := OS.get_environment("WORLD_AUTOTEST_WHO")
	if not who_list.is_empty():
		var names := who_list.split(",")
		for slot: int in Game.local_inputs.keys():
			Game.set_local_style(slot, {"who": names[slot % names.size()]})
	# Exercise the customization RPCs the way HUD swatch clicks would —
	# unless a run pinned specific characters, which this would undo.
	if who_list.is_empty():
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			for slot: int in Game.local_inputs.keys():
				Game.cycle_local_style(slot, AvatarFactory.ATTRS[slot % 2], 1))
	# WORLD_AUTOTEST_BLOCK=<id>: pin every bot's hotbar to one block so a
	# smoke test can hammer a specific mechanic (booms, warp stones...).
	# WORLD_AUTOTEST_SERVER_BOTS=<n>: ask the server for n computer players
	# so headless runs exercise the server-side bot AI.
	var server_bots := OS.get_environment("WORLD_AUTOTEST_SERVER_BOTS")
	if server_bots.is_valid_int() and server_bots.to_int() > 0:
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if Game.world != null:
				for i in server_bots.to_int():
					Game.world.sv_add_bot.rpc_id(1))
	# WORLD_AUTOTEST_MATCH=1 starts one battle. A number ABOVE 1 is a repeat
	# interval in seconds, which is how anything that must be the same from
	# one round to the next gets checked — where each team starts, most of
	# all. One battle can never show that; it takes two and a comparison.
	# WORLD_AUTOTEST_MODE=creative|battle|ctf: pick the game mode before the
	# first round starts. Without it a headless run can only ever exercise
	# whatever mode the server happens to be in, which is no way to test a
	# new one.
	var mode_hook := OS.get_environment("WORLD_AUTOTEST_MODE")
	if not mode_hook.is_empty():
		get_tree().create_timer(4.5).timeout.connect(func() -> void:
			if Game.world != null:
				Game.world.sv_set_mode.rpc_id(1, mode_hook))
	var match_hook := OS.get_environment("WORLD_AUTOTEST_MATCH")
	if match_hook.is_valid_int() and match_hook.to_int() >= 1:
		var start_battle := func() -> void:
			if Game.world != null:
				Game.world.sv_match_start.rpc_id(1, 0)
				for slot: int in Game.local_inputs.keys():
					Game.set_local_team(slot, slot % 4)
		get_tree().create_timer(6.0).timeout.connect(start_battle)
		var every := match_hook.to_int()
		if every > 1:
			var repeat := Timer.new()
			repeat.wait_time = float(every)
			# sv_match_start is ignored while a battle is already running,
			# so this simply picks up whenever the table is idle again.
			repeat.timeout.connect(start_battle)
			add_child(repeat)
			repeat.start()
	# WORLD_SHOWCASE=1: plant a strip of every foliage/shaped block near
	# spawn so a screenshot run can judge the look deterministically.
	if OS.get_environment("WORLD_SHOWCASE") == "1":
		get_tree().create_timer(9.0).timeout.connect(func() -> void:
			var world := Game.world
			if world == null or world.chunks == null or world.players == null:
				return
			var anchor: Player = null
			for child in world.players.get_children():
				if child is Player and child.is_local:
					anchor = child
					break
			if anchor == null:
				return
			var ids := [Blocks.TALL_GRASS, Blocks.FERN, Blocks.FLOWER_RED,
				Blocks.FLOWER_YELLOW, Blocks.BLUEBELL, Blocks.DAISY,
				Blocks.MUSHROOM, Blocks.SAPLING, Blocks.BERRY_BUSH,
				Blocks.WHEAT_PLANT, Blocks.CATTAIL, Blocks.DEAD_BUSH,
				Blocks.BAMBOO, Blocks.TORCH, Blocks.FIRE]
			for i in ids.size():
				var wx := int(anchor.position.x) - 7 + i
				var wz := int(anchor.position.z) - 5
				var wy: int = world.chunks.ground_height(wx, wz) + 1
				world.send_edit(anchor.slot, Vector3i(wx, wy, wz), ids[i]))
	if OS.get_environment("WORLD_AUTOTEST_SURVIVAL") == "1":
		get_tree().create_timer(8.0).timeout.connect(func() -> void:
			if Game.world != null:
				Game.world.sv_survival_start.rpc_id(1, 0))
	var forced := OS.get_environment("WORLD_AUTOTEST_BLOCK")
	if forced.is_valid_int():
		var pin := Timer.new()
		pin.wait_time = 2.0
		pin.timeout.connect(func() -> void:
			for child in Game.world.players.get_children():
				if child is Player and child.is_local:
					child.slots[2] = {"kind": "block", "id": forced.to_int()}
					child.selected_slot = 2)
		add_child(pin)
		pin.start()

func _on_server_lost() -> void:
	# Remember who was playing so the same seats come back by themselves.
	_rejoin = Game.local_inputs.values().duplicate()
	# Re-read the address: the world menu may have just repointed us.
	_want_url = _target_url()
	Game.reset_to_disconnected()
	_in_world = false
	# The menu node survives and gets re-pointed at the new world in
	# _on_connected, exactly like the first connection does.
	_attempts = 0
	_show_screen(_connect_screen)
	_retry_soon("Lost the world — reconnecting…")

## Drives the dial-retry loop: times out a stuck attempt, fires the next
## one when its moment comes. Runs every frame, in and out of the world.
func _poll_connection() -> void:
	if _in_world:
		return
	var now := Time.get_ticks_msec()
	if _connecting:
		if now - _connect_started_ms > int(CONNECT_TIMEOUT * 1000.0):
			_retry_soon(_waiting_text())
		return
	if _retry_at_ms > 0 and now >= _retry_at_ms:
		_dial()

func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text

## Top-right minimap: top-block colors around the local players plus dots
## (gold = you, red = everyone else).
func _update_minimap() -> void:
	if not _in_world or Game.world == null or Game.world.chunks == null \
			or Game.world.players == null:
		return
	var center := Vector3(Game.world.spawn_pos)
	var locals: Array = []
	for child in Game.world.players.get_children():
		if child is Player and child.is_local:
			locals.append(child.position)
	if not locals.is_empty():
		center = Vector3.ZERO
		for pos: Vector3 in locals:
			center += pos
		center /= locals.size()
	var image := Image.create(96, 96, false, Image.FORMAT_RGB8)
	for py in 96:
		for px in 96:
			var wx := int(center.x) + (px - 48) * 2
			var wz := int(center.z) + (py - 48) * 2
			var block: int = Game.world.chunks.top_block(wx, wz)
			var color := Color(0.06, 0.07, 0.1)
			if block > 0:
				color = Blocks.top_color_of(block)
			image.set_pixel(px, py, color)
	if Game.world.match_phase == "BATTLE" and Game.world.storm_radius > 0.0:
		var ring: float = Game.world.storm_radius
		for angle_i in 140:
			var a := angle_i * TAU / 140.0
			var px := 48 + int((Game.world.storm_center.x + cos(a) * ring - center.x) / 2.0)
			var py := 48 + int((Game.world.storm_center.z + sin(a) * ring - center.z) / 2.0)
			if px >= 0 and px < 96 and py >= 0 and py < 96:
				image.set_pixel(px, py, Color(1.0, 0.25, 0.2))
	for child in Game.world.players.get_children():
		if child is Player:
			var px := 48 + int((child.position.x - center.x) / 2.0)
			var py := 48 + int((child.position.z - center.z) / 2.0)
			if px >= 1 and px < 95 and py >= 1 and py < 95:
				var dot := Color("ffd166") if child.is_local else Color("ff4426")
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						image.set_pixel(px + dx, py + dy, dot)
	_minimap.texture = ImageTexture.create_from_image(image)
	# The 3-player layout's fourth quarter shows a wide shared battle map.
	if _split != null and _split.big_map != null and is_instance_valid(_split.big_map):
		var wide := Image.create(120, 120, false, Image.FORMAT_RGB8)
		for py in 120:
			for px in 120:
				var wx := int(center.x) + (px - 60) * 4
				var wz := int(center.z) + (py - 60) * 4
				var block: int = Game.world.chunks.top_block(wx, wz)
				var color := Color(0.06, 0.07, 0.1)
				if block > 0:
					color = Blocks.top_color_of(block)
				wide.set_pixel(px, py, color)
		for child in Game.world.players.get_children():
			if child is Player:
				var px := 60 + int((child.position.x - center.x) / 4.0)
				var py := 60 + int((child.position.z - center.z) / 4.0)
				if px >= 1 and px < 119 and py >= 1 and py < 119:
					var dot := Color("ffd166") if child.is_local else Color("ff4426")
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							wide.set_pixel(px + dx, py + dy, dot)
		_split.big_map.texture = ImageTexture.create_from_image(wide)


## Applies the video settings (Game.video) everywhere. Each setting maps
## to exactly one thing — no presets, no automatic overrides.
func _unhandled_input(event: InputEvent) -> void:
	# ` opens the world menu — NOT Escape. In a browser Escape is the
	# browser's own key for releasing the mouse: pressing it dropped you
	# out of mouse-look and handed you a menu you never asked for, and
	# the game cannot take that key back. ` sits just below Escape, means
	# nothing else in the game, and no browser claims it.
	#
	# Escape still CLOSES the menu, because backing out with it is
	# universal and by then the cursor is already free either way.
	# Controllers never reach any of this — their Start button opens each
	# player's own build menu instead.
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).keycode
	# The end-of-battle table goes first: while it is up, Space, Enter and
	# Escape all dismiss it. Its Close button holds focus and would catch
	# Enter on its own, but focus is one grab_focus away from being
	# somewhere else, and this screen must never be a dead end.
	if is_instance_valid(final_scores.panel) \
			and key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		if final_scores.dismissable():
			final_scores.hide_now()
			get_viewport().set_input_as_handled()
		return
	# G OPENS THE WORLD MENU. It was the backtick, which is correct in the
	# sense that a browser will not give up Escape — and useless in the
	# sense that a nine-year-old does not know what a backtick is, cannot
	# find it, and would not guess it was a menu key if they did. The old
	# key still works so nothing anybody has learned stops working.
	var open_menu := key == KEY_G or key == KEY_QUOTELEFT
	var close_menu := key == KEY_ESCAPE and _world_menu != null \
		and _world_menu.visible
	if open_menu or close_menu:
		if _world_menu != null:
			# One modal at a time. Opening this used to draw it OVER an
			# already-open YOUR STUFF, and closing it revealed that one
			# still sitting there — two menus deep, both of them freezing
			# the player, with no clue that was what had happened.
			if not _world_menu.visible:
				_split.close_all_menus()
			_world_menu.toggle()
			_update_cursor_release()
			get_viewport().set_input_as_handled()

func _apply_video() -> void:
	var v: Dictionary = Game.video
	# Renderer-wide toggles that hold whether or not a world exists yet.
	RenderingServer.set_debug_generate_wireframes(true)
	if Game.world != null and Game.world.sky != null:
		Game.world.sky.allow_shadows = bool(v.shadows)
		var fog_end := float(int(v.dist_blocks))
		Game.world.sky.environment.fog_depth_end = fog_end
		Game.world.sky.environment.fog_depth_begin = fog_end * 0.55
		Game.world.sky.environment.ssao_enabled = bool(v.ssao)
		Game.world.sky.environment.glow_enabled = bool(v.glow)
	if Game.world != null and Game.world.chunks != null:
		Game.world.chunks.light_cap = 8 if bool(v.lights) else 0
		Game.world.chunks.set_water_shine(bool(v.water_shine))
		var want_ao := 0.16 if bool(v.ao) else 0.0
		if not is_equal_approx(Mesher.ao_step, want_ao):
			Mesher.ao_step = want_ao
			Game.world.chunks.remesh_all()
	if _split != null:
		_split.set_render_scale(clampf(int(v.render_scale) / 100.0, 0.01, 1.0))
		_split.set_wireframe(bool(v.wire))
	if OS.get_environment("WORLD_VIDEO_DEBUG") == "1" and Game.world != null 			and Game.world.sky != null:
		print("VIDEOCHECK glow=%s ssao=%s shadows=%s lightcap=%s" % [
			Game.world.sky.environment.glow_enabled,
			Game.world.sky.environment.ssao_enabled,
			Game.world.sky.allow_shadows,
			Game.world.chunks.light_cap if Game.world.chunks else -1])
	RenderingServer.directional_shadow_atlas_set_size(
		[1024, 2048, 4096][clampi(int(v.shadow_quality), 0, 2)], true)

## Everything top-right scales with the window: map ~24% of height.
func _layout_topright() -> void:
	if _minimap == null:
		return
	var window := Vector2(DisplayServer.window_get_size())
	var map_px := clampf(window.y * 0.24, 150.0, 460.0)
	var clock_y := 6.0
	_minimap.custom_minimum_size = Vector2(map_px, map_px)
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(window.x - map_px - 12, 12)
	_minimap.size = Vector2(map_px, map_px)
	_clock_label.add_theme_font_size_override("font_size", int(22 * ui_scale()))
	_players_label.add_theme_font_size_override("font_size", int(16 * ui_scale()))
	_wave_label.add_theme_font_size_override("font_size", int(22 * ui_scale()))
	# Clock and player count live top-CENTER so they never sit on top of
	# any player's radar (each cell has its own radar top-right).
	_clock_label.position = Vector2(window.x * 0.5 - map_px * 0.5, clock_y)
	_clock_label.size.x = map_px
	_players_label.position = Vector2(window.x * 0.5 - map_px * 0.5, clock_y + 30 * ui_scale())
	_players_label.size.x = map_px
	_wave_label.position = Vector2(window.x * 0.5 - map_px * 0.5, clock_y + 56 * ui_scale())
	_wave_label.size.x = map_px

func _refresh_match() -> void:
	var world := Game.world
	if world == null:
		return
	var phase: String = world.match_phase
	_lobby_panel.visible = false  # the lobby lives in each player's menu now
	if phase == "LOBBY":
		_rebuild_team_rows()
	elif phase == "END":
		pass  # cl_match_end banner below

func _rebuild_team_rows() -> void:
	for child in _team_rows.get_children():
		child.queue_free()
	var me := multiplayer.get_unique_id()
	for id: String in Game.roster.keys():
		var entry: Dictionary = Game.roster[id]
		var is_bot: bool = entry.get("bot", false)
		var is_mine: bool = entry.peer == me and Game.local_inputs.has(entry.slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(8 * ui_scale()))
		var who := _make_label(("🤖 " if is_bot else "") + str(entry.name) + ":", 20,
			Color.WHITE if is_mine or is_bot else Color(1, 1, 1, 0.55))
		row.add_child(who)
		for t in 4:
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.text = WorldNode.TEAM_NAMES[t]
			btn.disabled = not (is_mine or is_bot)
			btn.add_theme_font_size_override("font_size", int(18 * ui_scale()))
			var col: Color = WorldNode.TEAM_COLORS[t]
			btn.add_theme_color_override("font_color",
				col if int(entry.get("team", -1)) != t else Color.BLACK)
			var team := t
			var s: int = entry.slot
			var target := id
			btn.pressed.connect(func() -> void:
				if is_mine:
					Game.set_local_team(s, team)
				else:
					Game.world.sv_set_bot_team.rpc_id(1, target, team)
				Sfx.play("pop", -4.0))
			row.add_child(btn)
		_team_rows.add_child(row)

func _refresh_survival() -> void:
	if _survival_button == null or Game.world == null:
		return
	_survival_button.visible = not Game.world.survival_active
	_wave_label.text = "Wave %d!" % Game.world.survival_wave \
		if Game.world.survival_active else ""

var _banner_sticky := false










## The cursor is captured for mouse-look and must be handed back while
## ANYTHING on top needs clicking. Both callers used to set the flag
## themselves, which is how the final table ended up with a cursor it
## could not use — one place to decide it now.
func _update_cursor_release() -> void:
	if _split == null:
		return
	_split.world_menu_open = (_world_menu != null and _world_menu.visible) \
		or is_instance_valid(final_scores.panel)

func _show_banner(text: String, sticky := false) -> void:
	_loading_label.visible = false
	_banner.text = text
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner_sticky = sticky
	_banner_shown_ms = Time.get_ticks_msec()
	if sticky:
		return  # stays until a player dismisses it (jump)
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(_banner, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void: _banner.visible = false)

var _last_local_sig := ""

func _on_roster_changed() -> void:
	if _lobby_panel != null and _lobby_panel.visible:
		_rebuild_team_rows()
	# Only rebuild the split screen when the set of local players actually
	# changed - name/style/team edits must not tear down open menus.
	# THE FIRST PERSON IN GETS THE MENU OPENED FOR THEM, once. Both menus
	# were undiscoverable until this round, and the world menu is where the
	# mode, the map and the computer players live — the things somebody
	# arriving on an empty server actually wants. Only for the host (the
	# first human), only once, and never on top of a round in progress.
	if not _showed_opening_menu and Game.local_inputs.size() > 0 \
			and _world_menu != null and Game.world != null \
			and Game.host_peer == multiplayer.get_unique_id() \
			and str(Game.world.match_phase) == "IDLE":
		_showed_opening_menu = true
		_split.close_all_menus()
		_world_menu.open()
		_update_cursor_release()
	var sig := str(Game.local_inputs.keys())
	if _split != null and sig != _last_local_sig:
		_last_local_sig = sig
		_split.update_layout()
	if _players_label != null:
		_players_label.text = "%d playing" % Game.roster.size()

# ------------------------------------------------------------------
# Per-frame: join/leave polling, clock display, ambient audio
# ------------------------------------------------------------------

var _connect_a_latch := true
var _backdrop: Control

func _process(_delta: float) -> void:
	if Net.is_server:
		return
	_poll_connection()
	if _connect_screen != null and _connect_screen.visible:
		# Blocks drift gently up the title screen; Ⓐ on any pad connects.
		if _backdrop != null:
			var view_h := float(DisplayServer.window_get_size().y)
			for cube: Control in _backdrop.get_children():
				cube.position.y -= float(cube.get_meta("speed")) * _delta
				cube.rotation += float(cube.get_meta("spin")) * _delta
				if cube.position.y < -90.0:
					cube.position.y = view_h + 40.0
		var a_down := false
		for pad in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(pad, JOY_BUTTON_A):
				a_down = true
				break
		if a_down and not _connect_a_latch:
			_on_connect_pressed()
		_connect_a_latch = a_down
	if not _in_world:
		return
	_poll_join_leave(_delta)
	final_scores.poll_dismiss()
	var world := Game.world
	if world == null:
		return
	if world.match_phase == "LOBBY" or world.match_phase == "COUNTDOWN":
		world.match_seconds = maxf(0.0, world.match_seconds - _delta)
	# Friendly hop-in hint while it's just one player pottering about —
	# and ALWAYS when nobody from this machine is playing, because then
	# it is the only thing telling you how to get back in.
	# Only the "room for one more" nudge lives here. When NOBODY from this
	# machine is playing, the split-screen view already fills the screen
	# with a much bigger BATTLEBOX / "press SPACE to jump in" prompt —
	# printing a second, smaller copy of the same instruction underneath
	# it just read as the game saying everything twice.
	if _join_hint != null:
		# ONLY WHEN THERE IS A SPARE CONTROLLER TO PICK UP. It used to
		# show whenever any pad was connected at all — which includes the
		# one the player is holding — so a single player on a single pad
		# was told, permanently, to press A on another controller.
		var spare_pad := false
		var claimed := _claimed_keys()
		for pad_id: int in Input.get_connected_joypads():
			if not claimed.has("dev:pad:%d" % pad_id):
				spare_pad = true
				break
		_join_hint.visible = Game.local_inputs.size() < Game.MAX_LOCAL \
			and world.match_phase == "IDLE" and spare_pad
		_join_hint.text = "🎮  New player?  Press Ⓐ on another controller to hop in!"
	# The per-player red warning lives in each PlayerHud now.
	_storm_tint.color.a = 0.0
	var clock: float = world.clock
	var hour := int(fposmod(clock * 24.0, 24.0))
	var night: bool = clock > 0.78 or clock < 0.22
	_clock_label.text = "%s %02d:00" % ["☾" if night else "☀", hour]
	Sfx.play_ambient("crickets" if night else "birds")

func _claimed_keys() -> Dictionary:
	var keys := {}
	for input: InputSlot in Game.local_inputs.values():
		keys[input.device_key()] = true
	return keys

var _last_join_ms := 0

func _poll_banner_dismiss() -> void:
	if not _banner_sticky or not _banner.visible:
		return
	# The result deserves a moment on screen: ignore presses for 5s,
	# then any main button clears it.
	if Time.get_ticks_msec() - _banner_shown_ms < 5000:
		return
	for input: InputSlot in Game.local_inputs.values():
		if input.is_primary_pressed() or input.is_dig_pressed() \
				or input.is_menu_pressed():
			_banner.visible = false
			_banner_sticky = false
			return

## A twin pad is a second enumeration of a controller someone already
## plays with: same joypad name, mirroring the same A press right now.
## One physical controller = one player. macOS sometimes enumerates the
## same controller under two device ids, and the ghost id mirrors every
## button and stick of the real one forever. So an unclaimed pad only
## becomes ELIGIBLE to join after its full input state has differed from
## every claimed pad for several consecutive frames — a real second
## controller diverges the instant a different kid touches it; a ghost
## never does. (A completely dead ghost can't press A, so it never joins
## either.) With no pads claimed yet there is nothing to mirror and the
## first press joins normally.
const _DIVERGE_FRAMES := 6
## Pads that have proved themselves a separate physical controller. Once
## in here, always eligible — see _pad_join_eligible.
var _pad_proven: Dictionary = {}
var _pad_diverge_count: Dictionary = {}

const _MIRROR_BUTTONS: Array = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X,
	JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
	JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_DPAD_UP,
	JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
const _MIRROR_AXES: Array = [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y,
	JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT,
	JOY_AXIS_TRIGGER_RIGHT]

func _mirrors_pad(candidate: InputSlot, claimed: InputSlot) -> bool:
	# Buttons ONLY. Axes lag a frame between the ghost and the real
	# device during fast stick motion, which read as false divergence
	# and let the ghost join anyway. Button states are discrete: a ghost
	# can never hold a button its twin isn't holding for 6 frames, while
	# a real second controller's A press is itself the divergence proof.
	return candidate.button_mask(_MIRROR_BUTTONS) \
		== claimed.button_mask(_MIRROR_BUTTONS)

func _pad_join_eligible(candidate: InputSlot) -> bool:
	if candidate.kind != InputSlot.Kind.GAMEPAD:
		return true
	var claimed_pads: Array = []
	for input: InputSlot in Game.local_inputs.values():
		if input is InputSlot and input.kind == InputSlot.Kind.GAMEPAD:
			claimed_pads.append(input)
	if claimed_pads.is_empty():
		return true
	var key := candidate.device_key()
	var mirrors_someone := false
	for other: InputSlot in claimed_pads:
		if _mirrors_pad(candidate, other):
			mirrors_someone = true
			break
	# PROOF LATCHES. It used to reset the counter to zero on any frame the
	# two pads happened to match — and that is why a second player could
	# not join. Two children both holding A is not a coincidence, it is
	# what children do: the moment the joiner pressed A, the player
	# already in the game was usually holding A too, they read as mirrors,
	# and the count went back to nothing on every single frame of the
	# press. With four pads connected exactly one could ever get in.
	#
	# Divergence only ever needs proving ONCE. A ghost duplicate mirrors
	# its twin every frame it exists, so it can never accumulate a count;
	# a real controller diverges within moments of being picked up, and
	# once it has, it is a real controller for good. So the count only
	# goes up, and it survives whatever the two pads happen to be doing
	# at the instant somebody presses to join.
	if not mirrors_someone:
		_pad_diverge_count[key] = int(_pad_diverge_count.get(key, 0)) + 1
	if int(_pad_diverge_count.get(key, 0)) >= _DIVERGE_FRAMES:
		_pad_proven[key] = true
	return bool(_pad_proven.get(key, false))

func _poll_join_leave(delta: float) -> void:
	_poll_banner_dismiss()
	# Unclaimed devices hop in with A — but only devices that have proven
	# they're a real separate controller (see _pad_join_eligible), never
	# while a menu is open, one join per press.
	var menu_open := _split != null and _split.any_menu_open()
	for slot: InputSlot in InputSlot.candidate_slots():
		var key := slot.device_key()
		if _claimed_keys().has(key):
			continue
		var eligible := _pad_join_eligible(slot)
		# Rising edge of "pressed AND eligible": a fresh press joins at
		# once when the pad has already proven itself, and a HELD press
		# joins the moment eligibility arrives (a brand-new second
		# controller proves divergence during the press itself).
		var wants_join := slot.is_primary_pressed() and eligible and not menu_open
		if wants_join and not _prev_pressed.get(key, false) \
				and Time.get_ticks_msec() - _last_join_ms > 700:
			_last_join_ms = Time.get_ticks_msec()
			Game.join_local(slot)
			_split.update_layout()
		_prev_pressed[key] = wants_join
	# Claimed devices leave by HOLDING their leave control.
	for slot_index: int in Game.local_inputs.keys().duplicate():
		var input: InputSlot = Game.local_inputs[slot_index]
		var key := input.device_key()
		if input.is_leave_pressed():
			_leave_hold[key] = _leave_hold.get(key, 0.0) + delta
			if _leave_hold[key] >= LEAVE_HOLD_SECONDS:
				_leave_hold.erase(key)
				Game.leave_local(slot_index)
				Sfx.play("pop")
				_split.update_layout()
		else:
			_leave_hold.erase(key)
