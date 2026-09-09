class_name RoundCard
extends PanelContainer
## THE CARD BEFORE A ROUND: what is about to happen, to whom, and how
## long until it does.
##
## A round used to open with "Next battle in 6" in the corner and, for
## the host, a settings menu over the top of it. What every game of this
## kind does instead is stop, say the name of the thing, count down, and
## tell you whose side you are on — so that when you land you already
## know who to run towards. That is this: the mode, a countdown, your
## team in its colour and the team-mates you have.
##
## It goes when the round is live — or the moment you press anything
## once you have landed. The server holds SETUP for six seconds after
## the drop, so the card used to sit over a game people were already
## playing; a click or a button from THIS seat takes it down for good.
##
## NO "CHANGE TEAM" HINT. It pointed at the player's own menu, which has
## nothing in it that changes teams — the table is set on the front page
## and by whoever opens the world menu.
##
## Its own node rather than a corner of player_hud.gd, which had grown
## past the point of being readable. It reaches back into the HUD for
## the seat, the world and the menu.

var hud: Node
var _kicker: Label
var _title: Label
var _team: Label
var _mates: Label
var _t := 0.0
## Pressed away for this round. Reset when the round is live.
var dismissed := false

func _init(p_hud: Node) -> void:
	hud = p_hud
	var sc: float = hud._uscale()
	add_theme_stylebox_override("panel", UiTheme.panel_box(sc))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.px(8, sc))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(UiTheme.px(380, sc), 0)
	add_child(box)
	_kicker = Label.new()
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kicker.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_NOTE, sc))
	_kicker.add_theme_font_override("font", UiTheme.display(sc, 1.6))
	_kicker.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	box.add_child(_kicker)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_TITLE + 12, sc))
	_title.add_theme_font_override("font", UiTheme.display(sc, -1.0, true))
	_title.add_theme_color_override("font_color", UiTheme.INK)
	box.add_child(_title)
	_team = Label.new()
	_team.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_team.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_BODY + 4, sc))
	_team.add_theme_font_override("font", UiTheme.display(sc, 0.0))
	box.add_child(_team)
	_mates = Label.new()
	_mates.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mates.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mates.custom_minimum_size = Vector2(UiTheme.px(380, sc), 0)
	_mates.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.T_BODY, sc))
	_mates.add_theme_color_override("font_color", UiTheme.INK_DIM)
	box.add_child(_mates)

## Up before the round, down once it is live or once this seat has
## pressed it away. Refilled a few times a second while it is up.
func tick(phase: String, delta: float) -> void:
	var pre_round := phase == "LOBBY" or phase == "SETUP"
	if not pre_round:
		dismissed = false
	var card_up: bool = pre_round and not hud._menu.visible and not dismissed
	visible = card_up
	if card_up:
		_t -= delta
		if _t <= 0.0:
			_t = 0.2
			_refresh(phase)
	else:
		_t = 0.0

## Any press from THIS seat, once the drop has happened, takes the card
## down. This seat's, so one child clicking does not clear the card from
## three other screens: the keyboard seat answers to keys and the mouse,
## a pad seat to buttons on its own device.
func _input(event: InputEvent) -> void:
	if not visible or hud.world == null or hud.world.match_phase != "SETUP":
		return
	if not _press_from_this_seat(event):
		return
	dismissed = true
	visible = false

func _press_from_this_seat(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	var seat: InputSlot = Game.local_inputs.get(hud.slot)
	if seat == null:
		return false
	if seat.kind == InputSlot.Kind.GAMEPAD:
		return event is InputEventJoypadButton and event.device == seat.device
	return event is InputEventMouseButton or event is InputEventKey

## Fill the card in for this phase: four labels, and one walk of the
## roster for the team-mates.
func _refresh(phase: String) -> void:
	var world: Node = hud.world
	var secs := int(ceil(world.match_seconds))
	_kicker.text = world.client_rules.kicker()
	if phase == "LOBBY":
		_title.text = ("Starting in %d" % secs) if secs > 0 else "Starting…"
	else:
		_title.text = "Get ready"
	var me: String = hud._me()
	var entry: Dictionary = Game.roster.get(me, {})
	var team := int(entry.get("team", -1))
	var names: Array = world.client_team_names
	# Everyone for themselves: a side each, so the side needs no name
	# and there is nobody to list.
	var solo := names.size() >= 2 and names.size() >= Game.roster.size()
	if team < 0 or team >= names.size():
		_team.text = "Picking your team…"
		_team.add_theme_color_override("font_color", UiTheme.INK_DIM)
		_mates.text = ""
		return
	var tint: Color = WorldNode.TEAM_COLORS[team % WorldNode.TEAM_COLORS.size()]
	if solo:
		_team.text = "Everyone for themselves"
		_team.add_theme_color_override("font_color", tint)
		_mates.text = "You are %s. Good luck." % str(names[team])
		return
	_team.text = "You're on %s" % str(names[team])
	_team.add_theme_color_override("font_color", tint)
	# People first, then the computer players, and no more than a few
	# names before "and N more": a side of twenty is not a sentence.
	var people: Array = []
	var bots: Array = []
	for rid: String in Game.roster.keys():
		if rid == me or int(Game.roster[rid].get("team", -2)) != team:
			continue
		if bool(Game.roster[rid].get("bot", false)):
			bots.append(str(Game.roster[rid].name))
		else:
			people.append(str(Game.roster[rid].name))
	people.sort()
	bots.sort()
	var mates: Array = people + bots
	if mates.is_empty():
		_mates.text = "On your own this round."
		return
	var shown: Array = mates.slice(0, 3)
	var line := "with " + ", ".join(shown)
	if mates.size() > shown.size():
		line += " and %d more" % (mates.size() - shown.size())
	_mates.text = line
