class_name LobbyScreen
extends Control
## THE FIRST THING ANYBODY SEES. Three screens, in the order the
## decisions are made:
##
##   HOME    play, or join one of the games running, or start one
##   NEW     what that new game IS — mode, world, size, length, who else
##   CODE    the two words that get a friend into the private one
##
## WHAT THIS USED TO BE, and why none of it survived: one 620-pixel
## column of stacked form fields. A gold Play button, then a heading, then
## a list, then a text box, then a checkbox, then another text box. The
## games actually running — the only thing on the screen that changes, and
## the reason to be looking at it — were fourth down the page in body
## text. And "start a new game" took a NAME and nothing else, so the mode,
## the map, the size and the round length could only be chosen from inside
## a world that had already been generated as something else.
##
## So the screen is now two columns and the right-hand one is a list of
## games with what they ARE written under them; and starting a game is a
## screen of its own that asks the questions a game needs answered before
## it exists. See game_setup.gd for that table, and lobby/lobby.py for
## what happens to the answers.
##
## THE FOUR-YEAR-OLD PATH HAS TO SURVIVE ALL OF IT. Play is the big ember
## button, it holds focus from the first frame, and it needs no reading:
## Space, Enter or Ⓐ joins the always-on world exactly as it always did.
## Everything else is beside it and optional.
##
## And everything here is REACHABLE WITHOUT A MOUSE. Every control on this
## screen was FOCUS_NONE once, which meant a gamepad could do exactly one
## thing with it: press Play. On the first screen of a game whose players
## are mostly holding controllers.
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
## The hero column and the games panel, in design pixels at scale 1.
const HERO_WIDTH := 620
const LIST_WIDTH := 560
## The setup screen's panel.
const SETUP_WIDTH := 940
## The bar pinned to the bottom of the setup screen: the button in it, and
## the air above and below. Its HEIGHT is these added up rather than a
## number of its own — it was 96, which is not 60 plus 18 twice, so the
## button sat two pixels nearer the top than the bottom. Two pixels is
## invisible until you look at it, and then it is all you can see.
const BAR_PAD := 18
const BAR_BUTTON := 60

func _bar_height() -> int:
	return _px(BAR_BUTTON) + _px(BAR_PAD) * 2 + maxi(1, int(round(_scale)))
## Room around the columns, and between them. Design pixels.
const PAGE_MARGIN := 40
const COLUMN_GAP := 56

var _api: LobbyClient
var _scale := 1.0

# --- the three screens ---
var _home: Control
var _setup: Control
var _code_panel: Control

# --- home ---
var _games_box: VBoxContainer
var _games_note: Label
var _status: Label
var _play_button: Button
var _code_edit: LineEdit
var _split_row: BoxContainer
## The spacer that lines the games list up with the tagline beside it.
## Only means anything while the two columns are side by side.
var _list_offset: Control

# --- new game ---
var _name_edit: LineEdit
var _create_button: Button
var _wanted: Dictionary = {}
## field name -> {value: Button}. Repainted, never rebuilt.
var _choices: Dictionary = {}
## field name -> the whole labelled group, hidden when the mode has no
## use for it.
var _groups: Dictionary = {}
## The note under a row, for the rows whose note changes with the answer.
var _notes: Dictionary = {}

# --- code ---
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
	_wanted = GameSetup.opening_choice()
	# The screen's own answer, alongside the game's. Public by default: a
	# game nobody can find is the surprising choice. Set HERE rather than
	# left absent, because an absent value matches neither chip and the
	# row opens with nothing lit — which reads as a question you have not
	# answered yet rather than one that has an answer.
	_wanted["private"] = false
	_api = LobbyClient.new()
	add_child(_api)
	_api.rooms_listed.connect(_show_rooms)
	_api.room_created.connect(_on_created)
	_api.lookup_finished.connect(_on_lookup)
	_api.failed.connect(_on_failed)
	_build()
	get_viewport().size_changed.connect(_reflow)
	refresh()
	# WORLD_LOBBY_SCREEN=new|code — open one of the other two screens at
	# boot, so tools/screenshot.sh can photograph them. Every other screen
	# in this game has a hook like this, and these two are behind button
	# presses a screenshot run cannot make.
	#
	# `code` shows a made-up code, because the real one comes from making
	# a real room. It is there to check that the panel LAYS OUT — which is
	# the only thing a picture can tell you and the thing that has been
	# wrong before: this screen exists because its predecessor drew for
	# exactly zero frames.
	match EnvConfig.text("WORLD_LOBBY_SCREEN", ""):
		"new":
			_open_setup.call_deferred()
		"code":
			_show_code.call_deferred("brave-otter", "Your game")

func _process(delta: float) -> void:
	# `visible` is this whole screen; `_home` is the half with the list on
	# it. On the other two there is nothing a refresh could change.
	if not visible or _home == null or not _home.visible:
		return
	_refresh_at -= delta
	if _refresh_at <= 0.0:
		refresh()

func refresh() -> void:
	_refresh_at = REFRESH_SECONDS
	_api.list_rooms()

## Two columns, or one. Flipped rather than rebuilt: a BoxContainer lays
## its children out the other way round the moment `vertical` changes, so
## a window somebody is dragging never destroys the text box they are
## typing a code into.
func _reflow() -> void:
	if _split_row == null:
		return
	# MEASURED, not guessed. This was a hand-picked "under 1180 design
	# pixels" threshold, and on a 900-wide window it worked out at 885 —
	# eight pixels under the width the two columns actually need, so the
	# page stayed in two columns and the games list ran off the right-hand
	# edge of the screen. Adding up what the columns are is the only
	# version of this that stays right when one of them changes width.
	var needed := _px(HERO_WIDTH) + _px(LIST_WIDTH) + _px(COLUMN_GAP) \
		+ _px(PAGE_MARGIN) * 2
	_split_row.vertical = get_viewport_rect().size.x < needed
	if _list_offset != null:
		_list_offset.visible = not _split_row.vertical

# ------------------------------------------------------------------
# Building
# ------------------------------------------------------------------

func _build() -> void:
	# Its own backdrop, first child so everything else sits on it. It used
	# to be pushed in from main.gd, which meant the screen depended on the
	# order somebody else added things in.
	add_child(TitleBackdrop.new())
	_home = _build_home()
	add_child(_home)
	_setup = _build_setup()
	_setup.visible = false
	add_child(_setup)
	_code_panel = _build_code_panel()
	_code_panel.visible = false
	add_child(_code_panel)
	_reflow()

## Which of the three is up. The other two are hidden outright rather
## than layered: a child pressing a button behind an overlay is a bug
## waiting to happen, and a focused control on a hidden screen is how the
## front page once ended up answering Space with a room code it did not
## have.
func _show(screen: Control, focus: Control) -> void:
	for child: Control in [_home, _setup, _code_panel]:
		if child != null:
			child.visible = child == screen
	if focus != null:
		focus.grab_focus()

# ------------------------------------------------------------------
# Home
# ------------------------------------------------------------------

func _build_home() -> Control:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)

	var pad := MarginContainer.new()
	for side: String in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, _px(PAGE_MARGIN))
	for side: String in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, _px(48))
	centre.add_child(pad)

	_split_row = BoxContainer.new()
	_split_row.add_theme_constant_override("separation", _px(COLUMN_GAP))
	pad.add_child(_split_row)
	_split_row.add_child(_build_hero())
	_split_row.add_child(_build_games_panel())
	return scroll

## The left column: what this is, and the one press that gets you in.
func _build_hero() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _px(10))
	column.custom_minimum_size = Vector2(_px(HERO_WIDTH), 0)
	# TOP, not centre. Two columns of different heights each centred on
	# their own middle line up on nothing: the heading over the games list
	# floated half way down beside the wordmark, which reads as a layout
	# that has come apart rather than as two columns.
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	column.add_child(_wordmark())
	column.add_child(_text("Build. Battle. Be the last one standing.",
		UiTheme.T_BODY + 2, UiTheme.INK_DIM))
	column.add_child(_gap(18))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", _px(12))
	column.add_child(buttons)

	# ONE BUTTON, and it starts a game.
	#
	# There were two: "Play now", which dropped you into the always-on
	# world, and "New game" beside it. The first was the confusing one —
	# a big primary button that made you a world nothing on the screen had
	# described, so on a quiet evening the front page's main action was
	# "here is a random game". The always-on world is in the list now,
	# saying what it is like every other game, and this button does the
	# thing the screen is for.
	_play_button = _primary_button("Start a game", UiTheme.T_TITLE)
	_play_button.pressed.connect(_open_setup)
	buttons.add_child(_play_button)
	# DEFERRED, because this column is not in the tree yet — it is being
	# built and gets added by the caller. grab_focus() on a node outside
	# the tree logs an error and does nothing, which quietly cost Play its
	# focus once and with it the whole point of the screen: Space, Enter
	# or Ⓐ doing the obvious thing without anyone reading a word.
	_play_button.call_deferred("grab_focus")

	column.add_child(_gap(10))
	_status = _text("", UiTheme.T_NOTE, UiTheme.ACCENT)
	_status.visible = false
	column.add_child(_status)

	column.add_child(_gap(22))
	column.add_child(_build_join_row())
	return column

## THE NAME OF THE GAME, as the neon sign the intro ends on. See
## neon_wordmark.gd — the front page used to say it in the same plain sans
## as the settings underneath, which is the game introducing itself in a
## voice it does not have anywhere else.
func _wordmark() -> Control:
	return NeonWordmark.new().setup(_scale)

## Somebody read you a code. Small, because it is the least common way in
## and it used to be a full-width form field with a heading over it.
func _build_join_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(10))
	var caption := _eyebrow("Got a code?")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_code_edit = _field("brave-otter")
	_code_edit.max_length = 40
	_code_edit.custom_minimum_size = Vector2(_px(220), _px(CONTROL_HEIGHT - 6))
	_code_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join_typed())
	row.add_child(_code_edit)
	var go := _ghost_button("Join", UiTheme.T_LABEL)
	go.custom_minimum_size = Vector2(0, _px(CONTROL_HEIGHT - 6))
	go.pressed.connect(_join_typed)
	row.add_child(go)
	return row

## The right column: what is actually running, and what each one IS.
func _build_games_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _px(12))
	column.custom_minimum_size = Vector2(_px(LIST_WIDTH), 0)
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# Level with the tagline rather than with the top of the wordmark: the
	# heading is a small upper-case label and the wordmark is 58px, so
	# sharing a top edge makes them look mis-set rather than aligned.
	# Stacked, there is nothing to line up WITH, so it goes away.
	_list_offset = _gap(96)
	column.add_child(_list_offset)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _px(14))
	head.add_child(_eyebrow("Playing right now"))
	var rule := HSeparator.new()
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.add_theme_stylebox_override("separator", _hairline())
	head.add_child(rule)
	column.add_child(head)

	# Says something from the first frame. An empty heading over an empty
	# box reads as broken, and the list only arrives a moment later — or
	# never, if the lobby is unreachable.
	_games_note = _text("Looking…", UiTheme.T_LABEL, UiTheme.INK_FAINT, true)
	column.add_child(_games_note)

	_games_box = VBoxContainer.new()
	_games_box.add_theme_constant_override("separation", _px(8))
	column.add_child(_games_box)
	return column

# ------------------------------------------------------------------
# The list
# ------------------------------------------------------------------

func _show_rooms(rooms: Array) -> void:
	# A list that arrived is the end of whatever went wrong last time.
	if _status != null and _status.visible and not _busy:
		_set_status("")
	for child in _games_box.get_children():
		child.queue_free()
	# THE ALWAYS-ON WORLD IS IN THE LIST. It used to be lifted out and
	# given a button of its own, which meant the one game guaranteed to be
	# running was the one game the screen never described.
	var others: Array = rooms
	if others.is_empty():
		# A titled hole reads as something that failed to load. An empty
		# list is a normal state and gets a box of its own saying so.
		_games_note.visible = false
		_games_box.add_child(_empty_card())
		return
	_games_note.visible = false
	for entry: Dictionary in others:
		_games_box.add_child(_room_row(entry))

## One game. The name and what it IS on the left, how busy it is on the
## right — and the state marked by a bar down the RIGHT edge, which is
## where the thing it is about already lives. (UiTheme.rail_box has the
## rest of that argument.)
func _room_row(entry: Dictionary) -> Button:
	var code := str(entry.get("code", ""))
	var display_name := str(entry.get("name", code))
	var who := _people_in(entry)
	var humans: int = who[0]
	var bots: int = who[1]
	var busy := humans > 0

	var row := Button.new()
	row.custom_minimum_size = Vector2(0, _px(70))
	row.tooltip_text = "Join %s" % code
	var rail := UiTheme.LIVE if busy else Color(0, 0, 0, 0)
	row.add_theme_stylebox_override("normal",
		UiTheme.rail_box(UiTheme.SURFACE_2, _scale, rail))
	for state: String in ["hover", "pressed", "focus"]:
		row.add_theme_stylebox_override(state,
			UiTheme.rail_box(UiTheme.SURFACE_3, _scale,
				rail if busy else UiTheme.ACCENT))
	row.pressed.connect(func() -> void: _join(code, display_name))

	# A Button cannot align two things independently, so the text lives in
	# a layout laid over it — and that layout must not eat the click.
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = _px(16)
	line.offset_right = -_px(18)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", _px(12))

	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", _px(2))
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(names)
	names.add_child(_row_label(display_name, UiTheme.T_BODY, UiTheme.INK))
	# WHAT THE GAME IS. Without this the list is names, and a name answers
	# none of the questions somebody choosing between two games is asking.
	# A room that did not report its settings — an older one — gets its
	# code instead of a made-up description.
	# WHAT THE GAME IS, and not how many computer players are in it. That
	# ran the line past the end of the card and into an ellipsis — and it
	# is not why anybody picks a game anyway. How many PEOPLE are in there
	# is, and that is on the right of this row in mint.
	var what := GameSetup.summary(entry.get("settings", {}))
	# The one game that is always there says so, because "why is this one
	# always at the top" is otherwise a question with no answer on screen.
	if bool(entry.get("house", false)):
		what = "Always open · " + what if not what.is_empty() else "Always open"
	names.add_child(_row_label(what if not what.is_empty() else code,
		UiTheme.T_NOTE, UiTheme.INK_FAINT))

	var crowd := HBoxContainer.new()
	crowd.add_theme_constant_override("separation", _px(8))
	crowd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crowd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(crowd)
	crowd.add_child(_dot(UiTheme.LIVE if busy else UiTheme.INK_FAINT))
	# THE SHORT FORM HERE, and the computer players said once on the line
	# above instead. The full sentence — "waiting for players + 20
	# computer players" — is wider than the space left beside a game's
	# name, so the label was squeezed to nothing and every row showed a
	# dot with no number against it.
	#
	# Lit for PEOPLE only. A room full of bots is not a room worth
	# highlighting, and colouring it as though it were is the same lie the
	# number used to tell.
	var count := _row_label("%d playing" % humans if busy else "waiting",
		UiTheme.T_NOTE, UiTheme.LIVE if busy else UiTheme.INK_FAINT)
	count.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	crowd.add_child(count)
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
# New game
# ------------------------------------------------------------------

## THE SCREEN THIS PAGE WAS MISSING. Every question a game needs answered
## is asked here, before the world exists — which is the only time any of
## them is free to answer. See game_setup.gd.
func _build_setup() -> Control:
	# A SCROLLING BODY UNDER A FIXED BAR, which is the shape every
	# settings sheet in every application has, and it is here for a
	# reason: the first version was one long scroll with "Create and
	# play" at the bottom of it, so on a 1280x800 screen the button that
	# does the thing was off the bottom edge. A page of options whose
	# only action is out of sight is a page that looks like it does not
	# work.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# THE ART GOES QUIET HERE. The backdrop has voxel cubes drifting
	# across it, which is right for a title screen and wrong behind eight
	# rows of settings: a cube passing over a line of text takes the line
	# with it. Same scrim the world menu uses, for the same reason.
	root.add_child(_scrim())

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -_bar_height()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)

	var pad := MarginContainer.new()
	for side: String in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, _px(40))
	for side: String in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, _px(44))
	centre.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _px(26))
	column.custom_minimum_size = Vector2(_px(SETUP_WIDTH), 0)
	pad.add_child(column)

	# --- header -------------------------------------------------------
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _px(16))
	column.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(_display("New game", UiTheme.T_TITLE + 6, UiTheme.INK))
	var back := _ghost_button("Back", UiTheme.T_LABEL)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close_setup)
	head.add_child(back)

	# --- what it is called, and who can find it -----------------------
	var name_card := _card(column)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", _px(10))
	name_card.add_child(name_row)
	_name_edit = _field("name your game (optional)")
	_name_edit.max_length = 32
	_name_edit.text_submitted.connect(func(_t: String) -> void: _create())
	name_row.add_child(_name_edit)
	name_card.add_child(_gap(2))
	# TWO CHOICES SIDE BY SIDE, like every other setting on this screen.
	#
	# It was one button with the current state written on it, which is a
	# control nobody can read: "Anyone can join" is equally plausibly what
	# is true now and what pressing it will do. Every other answer on this
	# page is a row you pick from, and this is an answer like any other.
	_build_choice_field(name_card, "private", "Who can join?", [
		{"value": false, "label": "Anyone can join"},
		{"value": true, "label": "Private — only with the code"}], "")

	# --- the mode, and then everything the mode implies ---------------
	_build_mode_field(column)
	_build_map_field(column)
	_build_choice_field(column, "size", "How big is the world?",
		_size_options(), "")
	_build_choice_field(column, "minutes", "How long is a round?",
		_length_options(), "")
	_build_choice_field(column, "target", "Captures to win",
		_target_options(), "")
	_build_choice_field(column, "teams", "How many teams?", _team_options(), "")
	_build_choice_field(column, "players", "How many players?",
		_player_options(), GameSetup.seats_note(GameSetup.DEFAULT_PLAYERS))
	_build_choice_field(column, "fly", "Who can fly?", _fly_options(), "")
	_build_choice_field(column, "revive", "Getting back up",
		_revive_options(), "")
	_build_choice_field(column, "drop", "When you are knocked out",
		_drop_options(), "")

	root.add_child(_build_action_bar())
	_refresh_setup()
	return root

## What you are about to make, and the button that makes it. Pinned to
## the bottom of the screen, so it is on screen whatever the window is
## and however many settings this grows to.
func _build_action_bar() -> Control:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -_bar_height()
	var box := UiTheme.flat(UiTheme.SURFACE, 0, _scale)
	var rule := maxi(1, int(round(_scale)))
	box.border_width_top = rule
	box.border_color = UiTheme.LINE
	box.content_margin_left = _px(PAGE_MARGIN)
	box.content_margin_right = _px(PAGE_MARGIN)
	# THE SAME ABOVE AND BELOW. The bar is a fixed height with one button
	# centred in it, and unequal margins tipped the button off centre by a
	# few pixels — which is exactly the sort of thing that reads as
	# "slightly wrong" without anybody being able to say why.
	# The hairline along the top is drawn INSIDE the box, over the content
	# area, so the top margin has to step past it or the button sits one
	# pixel higher than it sits low.
	box.content_margin_top = _px(BAR_PAD) + rule
	box.content_margin_bottom = _px(BAR_PAD)
	bar.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(20))
	bar.add_child(row)

	# NO SUMMARY LINE. It read back the settings you had just chosen —
	# "Battle royale · Island · 200 across · 5 min" — three centimetres
	# under the buttons that say the same thing, highlighted. Nobody
	# checks a sentence when the answers themselves are on screen.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_create_button = _primary_button("Create and play", UiTheme.T_TITLE - 6)
	_create_button.custom_minimum_size = Vector2(_px(300), _px(BAR_BUTTON))
	# FILL, not shrink-centre: the bar is exactly the button plus its
	# padding, so filling the space IS being centred in it, and there is
	# no rounding left over to land on one side.
	_create_button.size_flags_vertical = Control.SIZE_FILL
	_create_button.pressed.connect(_create)
	row.add_child(_create_button)
	return bar

## The mode: bigger than the rest, because it decides which of the rest
## are even asked.
func _build_mode_field(parent: Control) -> void:
	var group := _group(parent, "mode", "How are we playing?", "")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(10))
	group.add_child(row)
	var buttons: Dictionary = {}
	for spec: Dictionary in GameSetup.MODES:
		var key := str(spec["key"])
		var tile := _tile(str(spec["label"]), str(spec["note"]))
		tile.pressed.connect(func() -> void: _pick("mode", key))
		row.add_child(tile)
		buttons[key] = tile
	_choices["mode"] = buttons

func _build_map_field(parent: Control) -> void:
	var options: Array = []
	for spec: Dictionary in GameSetup.MAPS:
		options.append({"value": str(spec["key"]), "label": str(spec["label"])})
	_build_choice_field(parent, "map", "Which world?", options, "")

## A labelled row of one-out-of-several buttons. Every field below the
## mode is one of these, which is what keeps them all the same size, the
## same shape and the same distance apart.
func _build_choice_field(parent: Control, field: String, title: String,
		options: Array, note: String) -> void:
	var group := _group(parent, field, title, note)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", _px(8))
	row.add_theme_constant_override("v_separation", _px(8))
	group.add_child(row)
	var buttons: Dictionary = {}
	for option: Dictionary in options:
		var value: Variant = option["value"]
		var chip := _chip(str(option["label"]))
		chip.pressed.connect(func() -> void: _pick(field, value))
		row.add_child(chip)
		buttons[value] = chip
	_choices[field] = buttons

func _size_options() -> Array:
	var out: Array = []
	for size: int in GameSetup.SIZES:
		out.append({"value": size, "label": GameSetup.size_label(size)})
	return out

func _fly_options() -> Array:
	var out: Array = []
	for answer: String in GameSetup.FLY_ANSWERS:
		out.append({"value": answer, "label": GameSetup.fly_label(answer)})
	return out

## Every length either mode offers, in one row. The row is rebuilt when
## the mode changes — see _refresh_setup — because the two modes do not
## offer the same lengths and pretending they do would put a button there
## that quietly means something else.
func _length_options() -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for mode: String in ["battle", "holdout"]:
		for minutes: int in GameSetup.lengths_for(mode):
			if seen.has(minutes):
				continue
			seen[minutes] = true
			out.append({"value": minutes, "label": GameSetup.length_label(minutes)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["value"]) < int(b["value"]))
	return out

func _target_options() -> Array:
	var out: Array = []
	for target: int in GameSetup.TARGETS:
		out.append({"value": target, "label": "First to %d" % target})
	return out

func _team_options() -> Array:
	var out: Array = []
	for count: int in GameSetup.TEAM_COUNTS:
		out.append({"value": count, "label": GameSetup.teams_label(count)})
	return out

func _player_options() -> Array:
	var out: Array = []
	for limit: int in GameSetup.PLAYER_LIMITS:
		out.append({"value": limit, "label": GameSetup.players_label(limit)})
	return out

func _revive_options() -> Array:
	var out: Array = []
	for rung: int in ReviveRule.choices(true):
		out.append({"value": rung, "label": ReviveRule.label(rung)})
	return out

func _drop_options() -> Array:
	return [{"value": false, "label": "Keep your weapons"},
		{"value": true, "label": "Drop them where you fell"}]

## Somebody chose something. One place, so every field is remembered the
## same way and repainted by the same pass.
func _pick(field: String, value: Variant) -> void:
	_wanted[field] = value
	if field == "mode":
		# Snapped back onto the table, so nothing survives a mode change
		# that the new mode has no button for. `private` is the screen's
		# own and is carried across by hand.
		var mine: bool = bool(_wanted.get("private", false))
		_wanted = GameSetup.clean(_wanted)
		_wanted["private"] = mine
	_refresh_setup()
	Sfx.play("tick", -8.0)

## Paint what is chosen, and hide what this mode has no use for. Cheap
## enough to call on every press: it repaints buttons, it never rebuilds
## them, so nothing you are half way through pressing disappears.
func _refresh_setup() -> void:
	var mode := str(_wanted.get("mode", GameSetup.DEFAULT_MODE))
	for field: String in _choices:
		var group: Control = _groups.get(field)
		if group != null:
			# `private` is the screen's own answer rather than one of the
			# game's, so GameSetup has no opinion about it and it is
			# always asked.
			group.visible = field == "private" or GameSetup.uses(field, mode)
		var buttons: Dictionary = _choices[field]
		for value: Variant in buttons:
			_paint_choice(buttons[value], value == _wanted.get(field))
	# The length row is shared between the two clocked modes, so the
	# lengths the OTHER one offers are disabled rather than removed: a row
	# that changes width when you pick a mode is a row that moves the
	# button under your finger.
	if _choices.has("minutes"):
		var allowed := GameSetup.lengths_for(mode)
		for value: Variant in _choices["minutes"]:
			var btn: Button = _choices["minutes"][value]
			btn.disabled = not (int(value) in allowed)
	# HOW MANY EACH SIDE GETS. The number of players and the number of
	# teams are two rows apart and only mean anything together, so the
	# players row is re-labelled whenever the teams change rather than
	# leaving somebody to divide one by the other.
	if _choices.has("players"):
		var teams := int(_wanted.get("teams", GameSetup.DEFAULT_TEAMS))
		var split := teams if GameSetup.uses("teams", mode) else 0
		var note: Label = _notes.get("players")
		if note != null:
			note.text = GameSetup.seats_note(int(_wanted.get("players", 0)), split)


## Back to the front, from outside. main.gd calls this when somebody
## leaves a game: the screen may have been left on the setup sheet or on
## a created game's code, and neither is where they want to arrive.
func back_to_front() -> void:
	_show(_home, _play_button)

func _open_setup() -> void:
	_set_status("")
	_show(_setup, _create_button)

func _close_setup() -> void:
	_show(_home, _play_button)

# ------------------------------------------------------------------
# The code for a private game
# ------------------------------------------------------------------

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
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_scrim())
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(_scale))
	centre.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", _px(10))
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		inner.add_theme_constant_override(side, _px(26))
	inner.custom_minimum_size = Vector2(_px(HERO_WIDTH), 0)
	card.add_child(inner)

	inner.add_child(_eyebrow("Your game is ready"))
	inner.add_child(_text("Nobody can join unless you give them this:",
		UiTheme.T_BODY, UiTheme.INK_DIM, true))
	# The code, as big as the wordmark on the front page. It is meant to
	# be read out across a room to somebody holding a tablet.
	_code_label = _display("", UiTheme.T_TITLE + 10, UiTheme.ACCENT)
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
	_go_button = _primary_button("Start playing", UiTheme.T_TITLE - 4)
	_go_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_go_button.pressed.connect(func() -> void: _join(_made_code, _made_name))
	inner.add_child(_go_button)
	inner.add_child(_text("You can read it again from the world menu (G) at any time.",
		UiTheme.T_NOTE, UiTheme.INK_FAINT, true))
	return root

## Swap the screen for the code. Not a dialog on top: there is nothing
## else to do here now.
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
	# Focus moves HERE, and only now — never while this panel is being
	# built, which is the same frame Play grabs it and would leave the
	# front page with its focus on a button inside a hidden panel.
	_show(_code_panel, _go_button)

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
	# Public by default: a game nobody can find is the surprising choice,
	# and hiding one should be a deliberate act.
	_api.create_room(_name_edit.text.strip_edges(),
		not bool(_wanted.get("private", false)), GameSetup.clean(_wanted))

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
		# The list is polled, so a failure is a moment rather than a state
		# — it says so where the list would be, and says nothing in the
		# status line under the button. That line used to read "Play still
		# works — it is always there", which named a button that no longer
		# exists and stayed up in ember after the list had loaded fine.
		if _games_note != null:
			_games_note.text = "Can't reach the games list — trying again…"
			_games_note.visible = true
		_set_status("")
	else:
		# A create that failed happened on the setup screen, and that is
		# where whoever pressed the button is still standing.
		if _setup != null and _setup.visible:
			_show(_home, _play_button)
		_set_status(message)

func _set_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	# An empty label still reserves a line, which left a hole under the
	# Play button whenever there was nothing to say.
	_status.visible = not text.is_empty()

## Escape backs out of the setup screen. Without it the only way off is
## the Back button, which a keyboard has to find first.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _setup == null or not _setup.visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_close_setup()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------
# Small builders
# ------------------------------------------------------------------

func _px(n: float) -> int:
	return UiTheme.px(n, _scale)

## WRAPPING IS OFF BY DEFAULT, and that is not a detail.
##
## A Label that wraps has no minimum width, so a container asks it how
## wide it wants to be and is told "one character". Every one of these
## used to wrap, and the wordmark came out as B / A / T / T / L / E down
## the left-hand edge with the rest of the page pushed off the bottom.
## Only the few labels that are really paragraphs ask for it.
func _text(body: String, size: int, color: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = body
	label.add_theme_font_size_override("font_size", UiTheme.px(size, _scale))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap \
		else TextServer.AUTOWRAP_OFF
	return label

## A heading, set in a weight the bundled font does not have. See
## UiTheme.heavy: everything on every screen used to be one weight, which
## is why no title on any of them read as a title.
func _display(body: String, size: int, color: Color) -> Label:
	var label := _text(body, size, color)
	label.add_theme_font_override("font", UiTheme.heavy(_scale, 0.7, -1.2))
	return label

## A small upper-case label. Letterspaced, because upper case at this size
## sets too tight to read otherwise.
func _eyebrow(body: String) -> Label:
	var label := _text(body.to_upper(), UiTheme.T_NOTE, UiTheme.INK_FAINT)
	label.add_theme_font_override("font", UiTheme.heavy(_scale, 0.25, 1.6))
	return label

## A label inside a Button's overlay. It must not eat the click, and
## every one of these forgot to say so at least once.
func _row_label(body: String, size: int, color: Color) -> Label:
	var label := _text(body, size, color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _gap(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _px(height))
	return spacer

## What the games list looks like with nothing in it. A bordered, dashed-
## feeling box rather than a line of grey text: the panel keeps its shape,
## so the column does not collapse to a heading and a sentence.
func _empty_card() -> Control:
	var card := PanelContainer.new()
	var box := UiTheme.flat(Color(1, 1, 1, 0.02), UiTheme.R_CARD, _scale, 1.0,
		UiTheme.LINE)
	box.set_content_margin_all(_px(20))
	card.add_theme_stylebox_override("panel", box)
	card.custom_minimum_size = Vector2(0, _px(110))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", _px(6))
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(inner)
	var line := _text("No other games right now", UiTheme.T_BODY, UiTheme.INK_DIM)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(line)
	var sub := _text("Press New game and this fills up", UiTheme.T_NOTE,
		UiTheme.INK_FAINT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(sub)
	return card

## A wash over the backdrop, so a screen of text can be read against it.
func _scrim() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = UiTheme.SCRIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dim

func _hairline() -> StyleBoxLine:
	var rule := StyleBoxLine.new()
	rule.color = UiTheme.LINE
	rule.thickness = maxi(1, int(round(_scale)))
	return rule

## A filled circle. Drawn as a rounded stylebox rather than a glyph: a
## bullet character depends on a font the machine may not have, and a
## missing one is a tofu box on the front page.
func _dot(color: Color) -> Control:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiTheme.flat(color, 999, _scale))
	pill.custom_minimum_size = Vector2(_px(9), _px(9))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pill

## A titled block on the setup screen, remembered so the mode can hide it.
func _group(parent: Control, field: String, title: String,
		note: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", _px(8))
	parent.add_child(group)
	group.add_child(_eyebrow(title))
	if not note.is_empty():
		var note_label := _text(note, UiTheme.T_NOTE, UiTheme.INK_FAINT, true)
		group.add_child(note_label)
		_notes[field] = note_label
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _px(8))
	group.add_child(body)
	# Keyed by the FIELD, which is what _refresh_setup hides it by. Keyed
	# by its title it looked right and never hid anything, because no mode
	# has a setting called "How long is a round?".
	_groups[field] = group
	return body

func _card(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(_scale))
	parent.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", _px(10))
	card.add_child(inner)
	return inner

## A text box a child can actually see and hit. The default LineEdit is
## about twelve pixels of text; this is T_BODY in a control tall enough to
## aim at with a mouse or a thumb.
func _field(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, _px(CONTROL_HEIGHT))
	edit.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_BODY, _scale))
	edit.add_theme_color_override("font_color", UiTheme.INK)
	edit.add_theme_color_override("font_placeholder_color", UiTheme.INK_FAINT)
	edit.add_theme_color_override("caret_color", UiTheme.ACCENT)
	# ROOM INSIDE THE BOX. UiTheme.flat() has no content margins, so text
	# and placeholder alike started hard against the left border — "name
	# your game (optional)" with its first letter touching the edge. The
	# theme's own LineEdit box has always had padding; these overrides
	# threw it away.
	edit.add_theme_stylebox_override("normal",
		_field_box(1.0, UiTheme.LINE))
	edit.add_theme_stylebox_override("focus",
		_field_box(2.0, UiTheme.ACCENT))
	edit.add_theme_stylebox_override("read_only",
		_field_box(1.0, UiTheme.LINE))
	return edit

func _field_box(border: float, edge: Color) -> StyleBoxFlat:
	var box := UiTheme.flat(Color(0, 0, 0, 0.30), UiTheme.R_CONTROL, _scale,
		border, edge)
	box.content_margin_left = _px(14)
	box.content_margin_right = _px(14)
	box.content_margin_top = _px(8)
	box.content_margin_bottom = _px(8)
	return box

## THE ONE BUTTON THE SCREEN IS BUILT AROUND. Ember, filled, dark text on
## it, and the only thing painted that colour anywhere on the page.
func _primary_button(label: String, size: int) -> Button:
	var button := Button.new()
	button.text = label
	# WIDE ENOUGH TO BE THE BUTTON. Sized off its own text it came out
	# barely larger than the ghost button beside it, and a primary action
	# that is the same size as the secondary one is not a primary action.
	button.custom_minimum_size = Vector2(_px(280), _px(78))
	button.add_theme_font_size_override("font_size", UiTheme.px(size, _scale))
	button.add_theme_font_override("font", UiTheme.heavy(_scale, 0.5, 1.0))
	# NO GLOW UNDER IT. A StyleBoxFlat shadow is not a blur — it is the
	# same rounded rectangle drawn larger — so an ember shadow behind an
	# ember button came out as a hard second rectangle around the first,
	# and the button looked like it had been pasted on. Ember on
	# near-black does not need help standing out.
	var rest := UiTheme.flat(UiTheme.ACCENT, UiTheme.R_CARD, _scale)
	var hot: StyleBoxFlat = rest.duplicate()
	hot.bg_color = UiTheme.ACCENT.lightened(0.14)
	var down: StyleBoxFlat = rest.duplicate()
	down.bg_color = UiTheme.ACCENT_DEEP
	button.add_theme_stylebox_override("normal", rest)
	button.add_theme_stylebox_override("hover", hot)
	button.add_theme_stylebox_override("focus", hot)
	button.add_theme_stylebox_override("pressed", down)
	button.add_theme_stylebox_override("disabled",
		UiTheme.flat(UiTheme.SURFACE_3, UiTheme.R_CARD, _scale))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		button.add_theme_color_override(state, UiTheme.ON_ACCENT)
	button.add_theme_color_override("font_disabled_color", UiTheme.INK_FAINT)
	return button

func _ghost_button(label: String, size: int) -> Button:
	var button := Button.new()
	button.text = "  %s  " % label
	button.custom_minimum_size = Vector2(0, _px(CONTROL_HEIGHT))
	button.add_theme_font_size_override("font_size", UiTheme.px(size, _scale))
	button.add_theme_color_override("font_color", UiTheme.INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal",
		UiTheme.lit_box(UiTheme.SURFACE_2, UiTheme.R_CONTROL, _scale))
	# "focus" is in this list, and that is the whole point of the list.
	# Every button on this screen used to be FOCUS_NONE, which meant a
	# gamepad could do exactly one thing here: press Play.
	for state: String in ["hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state,
			UiTheme.flat(UiTheme.SURFACE_3, UiTheme.R_CONTROL, _scale, 1.0,
				UiTheme.ACCENT))
	return button

## One choice out of a row of them.
func _chip(label: String) -> Button:
	var button := _ghost_button(label, UiTheme.T_LABEL)
	button.custom_minimum_size = Vector2(0, _px(46))
	return button

## A mode: a name, and one line saying what it is. Bigger than a chip
## because it is the decision the rest of the screen hangs off.
func _tile(label: String, note: String) -> Button:
	var button := Button.new()
	# TALL ENOUGH FOR THE SECOND LINE. At 96 the note wrapped to two lines
	# and the second one was drawn outside the tile, over the heading of
	# the next section — which looked like the layout had given up rather
	# than like a tile with a description on it.
	button.custom_minimum_size = Vector2(0, _px(132))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paint_choice(button, false)

	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = _px(14)
	inner.offset_right = -_px(14)
	inner.offset_top = _px(14)
	inner.offset_bottom = -_px(12)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", _px(4))
	var title := _row_label(label, UiTheme.T_LABEL, UiTheme.INK)
	title.add_theme_font_override("font", UiTheme.heavy(_scale, 0.4, 0.0))
	inner.add_child(title)
	var sub := _text(note, UiTheme.T_NOTE, UiTheme.INK_FAINT, true)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(sub)
	button.add_child(inner)
	return button

## Paints the chosen entry. Cheap to call every refresh: it only writes
## styleboxes, so nothing is rebuilt and nothing loses focus.
##
## A TINT AND AN OUTLINE, not a solid fill. A row of solid ember buttons
## with one of them ember is a row with nothing chosen in it, and filling
## the chosen one solid is what forced the old menu to swap the label's
## colour too, which is a second thing to get wrong.
func _paint_choice(button: Button, on: bool) -> void:
	var fill := UiTheme.ACCENT_SOFT if on else UiTheme.SURFACE_2
	var edge := UiTheme.ACCENT if on else UiTheme.LINE
	var rest := UiTheme.flat(fill, UiTheme.R_CONTROL, _scale, 1.0, edge)
	var hot := UiTheme.flat(UiTheme.SURFACE_3 if not on else fill,
		UiTheme.R_CONTROL, _scale, 2.0, UiTheme.ACCENT)
	button.add_theme_stylebox_override("normal", rest)
	for state: String in ["hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, hot)
	button.add_theme_stylebox_override("disabled",
		UiTheme.flat(Color(UiTheme.SURFACE_2.r, UiTheme.SURFACE_2.g,
			UiTheme.SURFACE_2.b, 0.4), UiTheme.R_CONTROL, _scale))
	button.add_theme_color_override("font_color",
		UiTheme.INK if on else UiTheme.INK_DIM)
	button.add_theme_color_override("font_disabled_color", UiTheme.INK_FAINT)
