class_name LobbyScreen
extends Control
## The first thing anybody sees: which game do you want to be in?
##
## THE FOUR-YEAR-OLD PATH HAS TO SURVIVE THIS SCREEN EXISTING. Play is the
## big gold button, it holds focus, and it needs no reading — Space, Enter
## or Ⓐ joins the always-on world exactly as pressing Play always did.
## Everything else is below it and optional.
##
## Everything else has to be legible too, which the first version was not:
## the create and join fields were default-sized LineEdits — about twelve
## pixels of text on a 1280-wide screen — next to a button drawn at 34.
## Anything a child is expected to hit is at least CONTROL_HEIGHT tall
## here, and anything they are expected to read is at least T_BODY.
##
## And everything here is REACHABLE WITHOUT A MOUSE. Every control on this
## screen was FOCUS_NONE, which meant a gamepad could do exactly one thing
## with it: press Play. Starting a game, making it private, picking one
## out of the list and typing a code were all mouse-only — on the first
## screen of a game whose players are mostly holding controllers.
##
## The screen has TWO states. The chooser, and — after making a private
## game — the code. See _build_code_panel for why the code gets a screen
## of its own rather than a line of status text.
##
## Emits `join_requested` with a room code. It connects to nothing itself:
## main.gd owns the socket and the reconnect loop, and a second one here
## is how you end up with two.

signal join_requested(code: String, display_name: String)

## How often the running-games list refreshes while somebody is looking at
## it. Slow: it is a handful of rooms and the person reading it is a child
## deciding, not a trader.
const REFRESH_SECONDS := 6.0
## Nothing a child has to hit is smaller than this, in design pixels.
const CONTROL_HEIGHT := 52
const COLUMN_WIDTH := 620

var _api: LobbyClient
var _scale := 1.0
var _games_box: VBoxContainer
var _games_note: Label
var _status: Label
var _name_edit: LineEdit
var _code_edit: LineEdit
var _public_toggle: CheckBox
var _create_button: Button
var _house_players: Label
var _chooser: Control
var _code_panel: Control
var _code_label: Label
var _link_label: LineEdit
var _link_group: Control
var _go_button: Button
var _made_code := ""
var _made_name := ""
var _refresh_at := 0.0
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scale = UiTheme.scale_for(get_viewport_rect().size)
	_api = LobbyClient.new()
	add_child(_api)
	_api.rooms_listed.connect(_show_rooms)
	_api.room_created.connect(_on_created)
	_api.lookup_finished.connect(_on_lookup)
	_api.failed.connect(_on_failed)
	_build()
	refresh()

func _process(delta: float) -> void:
	# `visible` is this whole screen; `_chooser` is the half with the list
	# on it. Once the code is up there is nothing on screen a refresh
	# could change, and the only thing left to do is press the button.
	if not visible or _chooser == null or not _chooser.visible:
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
	# Its own backdrop, first child so everything else sits on it. It used
	# to be pushed in from main.gd, which meant the screen depended on the
	# order somebody else added things in.
	add_child(_backdrop())

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	# Everything below is the CHOOSER. It gets swapped out wholesale when
	# a private game is made, because at that moment there is exactly one
	# thing worth reading on the screen and it is not a list of options.
	_chooser = scroll
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _px(14))
	column.custom_minimum_size = Vector2(_px(COLUMN_WIDTH), 0)
	centre.add_child(column)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, _px(18))
	column.add_child(pad)
	column.add_child(_text("BattleBox", UiTheme.T_TITLE + 8, UiTheme.ACCENT, 6))
	column.add_child(_text("Build. Battle. Be the last one standing.",
		UiTheme.T_BODY, UiTheme.INK_DIM))

	# THE always-on world, as its own card. It is not one row in a list of
	# equals: it is the game, and the one a child gets to without reading.
	column.add_child(_gap(6))
	column.add_child(_house_card())

	_status = _text("", UiTheme.T_NOTE, UiTheme.INK_FAINT)
	_status.visible = false
	column.add_child(_status)

	# What else is running. Empty is a normal state and says so, rather
	# than leaving a titled hole.
	column.add_child(_gap(4))
	column.add_child(_heading("OTHER GAMES RUNNING NOW"))
	# Says something from the first frame. An empty heading over an empty
	# box reads as broken, and the list only arrives a moment later — or
	# never, if the lobby is unreachable.
	_games_note = _text("Looking…", UiTheme.T_LABEL, UiTheme.INK_FAINT)
	_games_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_games_note)
	_games_box = VBoxContainer.new()
	_games_box.add_theme_constant_override("separation", _px(6))
	column.add_child(_games_box)

	column.add_child(_gap(4))
	column.add_child(_build_create())
	column.add_child(_gap(4))
	column.add_child(_build_join())
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, _px(24))
	column.add_child(tail)

	_code_panel = _build_code_panel()
	_code_panel.visible = false
	add_child(_code_panel)

## Made a private game — so stop, and say the code.
##
## THIS SCREEN EXISTS BECAUSE THE MESSAGE DID NOT WORK. The code used to
## go into the status line, one call before the screen was swapped for the
## connecting screen: it was set and then hidden in the same frame, so it
## drew for exactly zero frames. A private game whose code nobody can read
## is a game nobody else can ever join, which is the entire feature gone —
## and it looked completely fine, because the label was definitely there.
##
## So the code gets a screen of its own that waits for a press. That is
## not friction; for a private game the code IS the thing you just made.
func _build_code_panel() -> Control:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(_scale))
	centre.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", _px(10))
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(side, _px(26))
	inner.custom_minimum_size = Vector2(_px(COLUMN_WIDTH), 0)
	card.add_child(inner)

	inner.add_child(_text("YOUR GAME IS READY", UiTheme.T_NOTE, UiTheme.INK_FAINT))
	inner.add_child(_text("Nobody can join unless you give them this:",
		UiTheme.T_BODY, UiTheme.INK_DIM))
	# The code, as big as the title on the front page. It is meant to be
	# read out across a room to somebody holding a tablet.
	_code_label = _text("", UiTheme.T_TITLE + 8, UiTheme.ACCENT, 6)
	inner.add_child(_code_label)

	# And the same thing as a link, because on the web that is what people
	# actually send each other. Selectable, so it can be copied — a Label
	# cannot be, and "copy" is the only thing anyone wants to do with it.
	# Grouped, so the whole idea can be hidden at once off the web rather
	# than leaving a caption over an empty box.
	_link_group = VBoxContainer.new()
	_link_group.add_theme_constant_override("separation", _px(6))
	_link_group.add_child(_gap(4))
	_link_group.add_child(_text("Or send them this link:",
		UiTheme.T_LABEL, UiTheme.INK_DIM))
	_link_label = _field("")
	_link_label.editable = false
	_link_label.add_theme_color_override("font_uneditable_color", UiTheme.INK)
	_link_group.add_child(_link_label)
	inner.add_child(_link_group)

	inner.add_child(_gap(6))
	var go := Button.new()
	go.text = "  Start playing  "
	go.custom_minimum_size = Vector2(0, _px(68))
	go.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_TITLE, _scale))
	var rest := UiTheme.flat(UiTheme.ACCENT, UiTheme.R_CARD, _scale)
	var hot := UiTheme.flat(UiTheme.ACCENT.lightened(0.16), UiTheme.R_CARD, _scale)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		go.add_theme_stylebox_override(state, rest if state == "normal" else hot)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		go.add_theme_color_override(state, UiTheme.ON_ACCENT)
	go.pressed.connect(func() -> void: _join(_made_code, _made_name))
	inner.add_child(go)
	inner.add_child(_text("You can read it again from the world menu (G) at any time.",
		UiTheme.T_NOTE, UiTheme.INK_FAINT))
	_go_button = go
	return centre

## Swap the chooser for the code. Not a dialog on top: there is nothing
## else to do on this screen now, and a child pressing a button behind an
## overlay is a bug waiting to happen.
func _show_code(code: String, display_name: String) -> void:
	_made_code = code
	_made_name = display_name
	_code_label.text = code
	var link := Room.link_for(Game.web_origin(), code)
	# Off the web there is no address to hand anybody, so the link half of
	# the card would just be an empty box promising something it has not
	# got. The code above it still works.
	_link_label.text = link
	_link_group.visible = not link.is_empty()
	_chooser.visible = false
	_code_panel.visible = true
	# Focus moves HERE, and only now.
	#
	# It used to be grabbed while this panel was being built, which is the
	# same frame Play grabs it — and this one ran second, so the front
	# page ended up with its focus on a button inside a hidden panel.
	# Space or Ⓐ, the one press the whole screen is designed around, would
	# then have joined a room with no code. Nothing about that is visible:
	# the front page looks right, and the button that answers is off
	# screen.
	_go_button.grab_focus()

## The always-on game: one big button, and how many people are in it.
func _house_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(_scale))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", _px(8))
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(side, _px(16))
	card.add_child(inner)

	var play := Button.new()
	play.text = "  ▶   Play  "
	play.custom_minimum_size = Vector2(0, _px(76))
	play.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_TITLE + 6, _scale))
	var rest := UiTheme.flat(UiTheme.ACCENT, UiTheme.R_CARD, _scale)
	var hot := UiTheme.flat(UiTheme.ACCENT.lightened(0.16), UiTheme.R_CARD, _scale)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		play.add_theme_stylebox_override(state, rest if state == "normal" else hot)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		play.add_theme_color_override(state, UiTheme.ON_ACCENT)
	play.pressed.connect(func() -> void: _join(Room.HOUSE_CODE, "BattleBox"))
	inner.add_child(play)
	# DEFERRED, because this card is not in the tree yet — it is being
	# built and gets added by the caller. grab_focus() on a node outside
	# the tree logs an error and does nothing, which quietly cost Play its
	# focus and with it the whole point of the screen: Space, Enter or Ⓐ
	# doing the obvious thing without anyone reading a word.
	play.call_deferred("grab_focus")

	_house_players = _text("the world everyone shares", UiTheme.T_NOTE, UiTheme.INK_FAINT)
	inner.add_child(_house_players)
	return card

## Start your own. One button does it; the name and the privacy switch sit
## beside it for anybody who wants them.
func _build_create() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(8))
	box.add_child(_heading("OR START YOUR OWN"))

	_name_edit = _field("name your game (optional)")
	_name_edit.max_length = 32
	_name_edit.text_submitted.connect(func(_t: String) -> void: _create())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(10))
	row.add_child(_name_edit)
	_create_button = _chunky_button("Start a new game")
	_create_button.pressed.connect(_create)
	row.add_child(_create_button)
	box.add_child(row)

	# Public by default: a game nobody can find is the surprising choice,
	# and hiding one should be a deliberate act.
	_public_toggle = CheckBox.new()
	_public_toggle.text = "  Anyone can join it"
	_public_toggle.button_pressed = true
	_public_toggle.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_LABEL, _scale))
	_public_toggle.add_theme_color_override("font_color", UiTheme.INK_DIM)
	_public_toggle.toggled.connect(func(on: bool) -> void:
		_public_toggle.text = "  Anyone can join it" if on \
			else "  Private — only people with the code")
	box.add_child(_public_toggle)
	return box

## Somebody read you a code.
func _build_join() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(8))
	box.add_child(_heading("GOT A CODE FROM A FRIEND?"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(10))
	_code_edit = _field("brave-otter")
	_code_edit.max_length = 40
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join_typed())
	row.add_child(_code_edit)
	var go := _chunky_button("Join")
	go.pressed.connect(_join_typed)
	row.add_child(go)
	box.add_child(row)
	return box

# ------------------------------------------------------------------
# The list
# ------------------------------------------------------------------

func _show_rooms(rooms: Array) -> void:
	for child in _games_box.get_children():
		child.queue_free()
	var others: Array = []
	for entry: Dictionary in rooms:
		if str(entry.get("code", "")) == Room.HOUSE_CODE:
			if _house_players != null:
				var who := _people_in(entry)
				_house_players.text = _crowd(who[0], who[1])
		else:
			others.append(entry)
	if others.is_empty():
		_games_note.text = "None right now — start one below and it will show up here."
		_games_note.visible = true
		return
	_games_note.visible = false
	for entry: Dictionary in others:
		_games_box.add_child(_room_row(entry))

func _room_row(entry: Dictionary) -> Button:
	var code := str(entry.get("code", ""))
	var display_name := str(entry.get("name", code))
	var who := _people_in(entry)
	var humans: int = who[0]
	var bots: int = who[1]
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, _px(CONTROL_HEIGHT + 6))
	row.add_theme_stylebox_override("normal",
		UiTheme.flat(UiTheme.SURFACE_2, UiTheme.R_CONTROL, _scale))
	for state: String in ["hover", "pressed", "focus"]:
		row.add_theme_stylebox_override(state,
			UiTheme.flat(UiTheme.SURFACE_3, UiTheme.R_CONTROL, _scale))
	row.tooltip_text = "Join %s" % code
	row.pressed.connect(func() -> void: _join(code, display_name))

	# The name on the left, how busy it is on the right. A Button cannot
	# align two things independently, so the text lives in a layout laid
	# over it — and that layout must not eat the click.
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = _px(16)
	line.offset_right = -_px(16)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", _px(12))
	var name_label := Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size",
		UiTheme.px(UiTheme.T_BODY, _scale))
	name_label.add_theme_color_override("font_color", UiTheme.INK)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)
	var count := Label.new()
	count.text = _crowd(humans, bots)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_NOTE, _scale))
	# Lit for PEOPLE only. A room full of bots is not a room worth
	# highlighting, and colouring it as though it were is the same lie the
	# number used to tell.
	count.add_theme_color_override("font_color",
		UiTheme.ACCENT if humans > 0 else UiTheme.INK_FAINT)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(count)
	row.add_child(line)
	return row

## "3 playing" reads better than "3", and "waiting for players" better
## than "0 playing", which sounds like something is broken.
##
## PEOPLE AND COMPUTER PLAYERS ARE COUNTED SEPARATELY, because the number
## is there to answer one question — is anybody in there? — and a total
## answers it wrongly. A room holding one child and eighteen bots said
## "19 playing", which is what a busy game looks like and is the reason
## somebody would choose it.
##
## So people lead, and the bots are an aside. A game with nobody in it
## says so even when it is full of them.
static func _crowd(humans: int, bots: int) -> String:
	var tail := ""
	if bots == 1:
		tail = " + 1 computer player"
	elif bots > 1:
		tail = " + %d computer players" % bots
	if humans <= 0:
		return "waiting for players" + tail
	if humans == 1:
		return "1 playing" + tail
	return "%d playing" % humans + tail

## What the lobby said, tolerating a room that only reported a total.
static func _people_in(entry: Dictionary) -> Array:
	var total := int(entry.get("players", 0))
	# `humans` is missing from a room old enough not to know about bots.
	# Counting its players as people is the right guess: the alternative
	# shows a busy game as empty.
	var humans := int(entry.get("humans", total))
	var bots := int(entry.get("bots", 0))
	return [humans, bots]

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
		_show_code(code, str(room.get("name", code)))
		return
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
	# A lobby that is down must never block Play: the always-on game is on
	# a fixed code, so it still works with nothing listed.
	if what == "list":
		if _games_note != null:
			_games_note.text = "Can't reach the games list right now."
			_games_note.visible = true
		_set_status("Play still works — it is always there")
	else:
		_set_status(message)

func _set_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	# An empty label still reserves a line, which left a hole under the
	# Play card whenever there was nothing to say.
	_status.visible = not text.is_empty()

# ------------------------------------------------------------------
# Small builders
# ------------------------------------------------------------------

## A quiet vertical wash, so the panels have something to sit against.
func _backdrop() -> TextureRect:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color("1b2233"), Color("0a0d15")])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _px(n: float) -> int:
	return UiTheme.px(n, _scale)

func _text(body: String, size: int, color: Color, outline := 0) -> Label:
	var label := Label.new()
	label.text = body
	label.add_theme_font_size_override("font_size", UiTheme.px(size, _scale))
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
		label.add_theme_constant_override("outline_size", _px(outline))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _heading(body: String) -> Label:
	var label := _text(body, UiTheme.T_NOTE, UiTheme.INK_FAINT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label

func _gap(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _px(height))
	return spacer

## A text box a child can actually see and hit. The default LineEdit is
## about twelve pixels of text; this is T_BODY in a control tall enough to
## aim at with a mouse or a thumb.
func _field(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, _px(CONTROL_HEIGHT))
	edit.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_BODY + 2, _scale))
	edit.add_theme_color_override("font_color", UiTheme.INK)
	edit.add_theme_color_override("font_placeholder_color", UiTheme.INK_FAINT)
	edit.add_theme_stylebox_override("normal",
		UiTheme.flat(UiTheme.SURFACE_2, UiTheme.R_CONTROL, _scale, 1.0, UiTheme.LINE))
	edit.add_theme_stylebox_override("focus",
		UiTheme.flat(UiTheme.SURFACE_3, UiTheme.R_CONTROL, _scale, 2.0, UiTheme.ACCENT))
	return edit

func _chunky_button(label: String) -> Button:
	var button := Button.new()
	button.text = "  %s  " % label
	button.custom_minimum_size = Vector2(0, _px(CONTROL_HEIGHT))
	button.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_BODY, _scale))
	button.add_theme_color_override("font_color", UiTheme.INK)
	button.add_theme_stylebox_override("normal",
		UiTheme.flat(UiTheme.SURFACE_2, UiTheme.R_CONTROL, _scale, 1.0, UiTheme.LINE))
	# "focus" is in this list, and that is the whole point of the list.
	# Every button on this screen used to be FOCUS_NONE, which meant a
	# gamepad could do exactly one thing here: press Play. Starting a
	# game, making it private, picking one out of the list and typing a
	# code were all mouse-only, on the first screen of a game designed to
	# be played on controllers by children who cannot read.
	for state: String in ["hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state,
			UiTheme.flat(UiTheme.SURFACE_3, UiTheme.R_CONTROL, _scale, 1.0, UiTheme.ACCENT))
	return button
