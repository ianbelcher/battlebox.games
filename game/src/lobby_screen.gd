class_name LobbyScreen
extends Control
## The first thing anybody sees: which game do you want to be in?
##
## The four-year-old path has to survive this screen existing. **Play** is
## the big gold button, it is focused, it needs no reading, and it goes
## straight into the always-on public game exactly as pressing Play always
## did. Everything else — the list of other games, starting your own,
## typing a friend's code — is smaller, below it, and entirely optional.
##
## Emits `join_requested` with a room code. It does not connect to
## anything itself: main.gd owns the socket and the reconnect loop, and
## this screen owning a second one is how you get two.

signal join_requested(code: String, display_name: String)

const GOLD := Color("ffd166")
const INK := Color(1, 1, 1, 0.75)
const FAINT := Color(1, 1, 1, 0.5)

## How often the public game list refreshes while somebody is looking at
## it. Slow, because it is a list of at most a handful of rooms and the
## person reading it is a child deciding, not a trader.
const REFRESH_SECONDS := 6.0

var _api: LobbyClient
var _rooms_box: VBoxContainer
var _status: Label
var _name_edit: LineEdit
var _code_edit: LineEdit
var _public_toggle: CheckBox
var _create_button: Button
var _refresh_at := 0.0
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_api = LobbyClient.new()
	add_child(_api)
	_api.rooms_listed.connect(_show_rooms)
	_api.room_created.connect(_on_created)
	_api.lookup_finished.connect(_on_lookup)
	_api.failed.connect(_on_failed)
	_build()
	refresh()

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_at -= delta
	if _refresh_at <= 0.0:
		refresh()

func refresh() -> void:
	_refresh_at = REFRESH_SECONDS
	_api.list_rooms()

# ------------------------------------------------------------------
# Building
# ------------------------------------------------------------------

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size = Vector2(560, 0)
	center.add_child(column)

	column.add_child(_label("BattleBox", 30, GOLD, 6))
	column.add_child(_label("Build. Battle. Be the last one standing.", 16, INK))

	# THE button. Everything else on this screen is optional and reads as
	# optional; this one is the game.
	var play := _big_button("  ▶  Play  ")
	play.pressed.connect(func() -> void: _join(Room.HOUSE_CODE, "BattleBox"))
	var play_holder := CenterContainer.new()
	play_holder.add_child(play)
	column.add_child(play_holder)
	play.grab_focus()

	_status = _label("", 15, FAINT)
	column.add_child(_status)

	column.add_child(_rule())
	column.add_child(_label("OTHER GAMES", 13, FAINT))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 150)
	column.add_child(scroll)
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 6)
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rooms_box)

	column.add_child(_rule())
	column.add_child(_build_create_row())
	column.add_child(_build_join_row())

## Start your own: name it, say whether strangers may see it, go.
func _build_create_row() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_label("START YOUR OWN GAME", 13, FAINT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "name your game"
	_name_edit.max_length = 32
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String) -> void: _create())
	row.add_child(_name_edit)
	# Public by default: a game nobody can find is the surprising choice,
	# and the private one is a deliberate act.
	_public_toggle = CheckBox.new()
	_public_toggle.text = "Anyone can join"
	_public_toggle.button_pressed = true
	_public_toggle.focus_mode = Control.FOCUS_NONE
	row.add_child(_public_toggle)
	_create_button = Button.new()
	_create_button.text = "Start"
	_create_button.focus_mode = Control.FOCUS_NONE
	_create_button.pressed.connect(_create)
	row.add_child(_create_button)
	box.add_child(row)
	return box

## Join a private one: the code a friend read out.
func _build_join_row() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_label("JOIN WITH A CODE", 13, FAINT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "brave-otter"
	_code_edit.max_length = 40
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join_typed())
	row.add_child(_code_edit)
	var go := Button.new()
	go.text = "Go"
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(_join_typed)
	row.add_child(go)
	box.add_child(row)
	return box

# ------------------------------------------------------------------
# Actions
# ------------------------------------------------------------------

func _create() -> void:
	if _busy:
		return
	_busy = true
	_create_button.disabled = true
	_set_status("Making your world…")
	# An unnamed game is not an error: the lobby names it after its code,
	# which is a perfectly good name and one less thing to demand of a
	# child who just wants to play.
	_api.create_room(_name_edit.text.strip_edges(), _public_toggle.button_pressed)

func _join_typed() -> void:
	var code := _code_edit.text.strip_edges().to_lower()
	if code.is_empty():
		return
	_set_status("Looking for %s…" % code)
	_api.look_up(code)

func _join(code: String, display_name: String) -> void:
	join_requested.emit(code, display_name)

func _on_created(room: Dictionary) -> void:
	_busy = false
	_create_button.disabled = false
	var code := str(room.get("code", ""))
	if code.is_empty():
		_set_status("The game would not start — try again")
		return
	if not bool(room.get("public", true)):
		# Say the code before leaving the screen; it is the only way
		# anybody else gets in, and it is about to be off-screen.
		_set_status("Your code is %s — tell your friends!" % code)
	_join(code, str(room.get("name", code)))

func _on_lookup(code: String, room: Dictionary) -> void:
	if room.is_empty():
		_set_status("No game called %s — check the code?" % code)
		return
	_join(code, str(room.get("name", code)))

func _on_failed(what: String, message: String) -> void:
	_busy = false
	if _create_button != null:
		_create_button.disabled = false
	# A lobby that is down must never block Play: the house room is on a
	# fixed code, so pressing Play still works with nothing listed.
	if what == "list":
		_set_status("Can't list the other games right now — Play still works")
	else:
		_set_status(message)

func _show_rooms(rooms: Array) -> void:
	for child in _rooms_box.get_children():
		child.queue_free()
	var others: Array = []
	for entry: Dictionary in rooms:
		if str(entry.get("code", "")) != Room.HOUSE_CODE:
			others.append(entry)
	if others.is_empty():
		var none := _label("No other games running — start one below!", 14, FAINT)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_rooms_box.add_child(none)
		return
	for entry: Dictionary in others:
		_rooms_box.add_child(_room_button(entry))

func _room_button(entry: Dictionary) -> Button:
	var code := str(entry.get("code", ""))
	var display_name := str(entry.get("name", code))
	var players := int(entry.get("players", 0))
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 38)
	button.text = "  %s      %s" % [display_name, _crowd(players)]
	button.tooltip_text = "Join %s" % code
	button.pressed.connect(func() -> void: _join(code, display_name))
	return button

## "3 playing" reads better than "3", and "empty" reads better than "0
## playing" — the second one sounds like something is broken.
static func _crowd(players: int) -> String:
	if players <= 0:
		return "empty"
	if players == 1:
		return "1 playing"
	return "%d playing" % players

func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text

# ------------------------------------------------------------------
# Small builders
# ------------------------------------------------------------------

func _label(text: String, size: int, color: Color, outline := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(size * Main.ui_scale()))
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
		label.add_theme_constant_override("outline_size", outline)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _rule() -> Control:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(0, 1)
	return line

func _big_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 34)
	var normal := StyleBoxFlat.new()
	normal.bg_color = GOLD
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 44
	normal.content_margin_right = 44
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = GOLD.lightened(0.15)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, hover if state != "normal" else normal)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		button.add_theme_color_override(state, Color("1c2333"))
	return button
