class_name BodyDirector
extends Node
## WHAT EACH PLAYER'S BODY IS: how big, how fast, which side it is on,
## and what happens when somebody swings at it.
##
## These are PRIMITIVES, not game rules. This node knows how to make a
## player a given size and how to tell everybody about it; WHY anybody is
## that size is entirely the mode's — Giants doubles you for a knockout,
## Tag makes whoever is It twice the size and twice as fast, and every
## game written before either of them never calls any of it and has
## players who are all exactly 1.0 forever.
##
## It is a director because the alternative was two hundred more lines in
## world.gd, which is the wire protocol and is already at the ceiling
## tests/unit/style_test.gd holds it to. What STAYS in world.gd is the two
## RPCs — every `@rpc` in the game is declared there and nowhere else —
## and they come straight back here, the way `cl_crates` goes to CrateView.
##
## UNLIKE the other directors, this one runs on BOTH sides: the decisions
## are the server's, but the client's copy of everybody's size and hearts
## is here too, because a body's size and a body's hearts are the same
## kind of fact and splitting them across two files is how one of them
## ends up stale.
##
## The arithmetic of what a size MEANS is one step further out again, in
## body_size.gd, which touches nothing at all and can be asked anything by
## a test with no world running.

var world: Node = null

## SERVER-OWNED, deliberately. A client that could set its own size could
## make itself small enough to be nearly unhittable, which is the one
## thing here worth being careful about. Clients hold a copy, written only
## by the RPC.
var sizes: Dictionary = {}

func size_of(id: String) -> float:
	return float(sizes.get(id, BodySize.PERSON))

## BECOME THIS BIG, and tell everybody. Clamped to what a body can be at
## all (BodySize.MIN/MAX); a mode's own cap belongs in the mode.
func set_size(id: String, size: float) -> void:
	if not multiplayer.is_server():
		return
	size = BodySize.clamped(size)
	if is_equal_approx(size_of(id), size):
		return
	sizes[id] = size
	_lift_clear(id, size)
	world.cl_size.rpc(id, size)
	# Hearts follow size in any mode that says so (Giants), and the bar
	# every HUD draws them against goes out with them — so this has to
	# come after the size itself, not before.
	world.send_hearts(id)

## A BODY THAT JUST GREW MAY BE INSIDE THE GROUND.
##
## The client eases itself out (Player.set_body_size, and _local_move's
## own "a block appeared where I am standing" rule behind it) and reports
## where it ended up at the next sv_pos, a twelfth of a second later. The
## server's own copy is lifted here rather than waiting for that, because
## between the two it is the one deciding what the storm is hurting and
## what a shot may hit.
##
## NOT a teleport RPC: the client is already handling itself, and moving
## somebody who is face-down waiting to be picked up would stand them
## somewhere they were never knocked down.
func _lift_clear(id: String, size: float) -> void:
	if size <= BodySize.PERSON:
		return          # only growing can bury you; the feet stay put
	var state: Dictionary = world.player_state.get(id, {})
	if state.is_empty():
		return
	var clear: Vector3 = world.store.safe_stand(Vector3(state.pos), 0.0)
	if clear.y <= float(state.pos.y):
		return
	state.pos = clear
	if world.bots.roster.has(id):
		world.bots.roster[id].pos = clear

## Everybody back to the size of a person. The match director calls it as
## a round is set up, for the same reason the storm picture is cleared
## there: a round begins as its mode makes it, not as the last one left
## it. Without this, Giants' second round opens with last round's winner
## already eight times everybody else.
func reset_sizes() -> void:
	if not multiplayer.is_server():
		return
	for id: String in sizes.keys():
		world.cl_size.rpc(id, BodySize.PERSON)
	sizes.clear()

## HOW FAST, as a multiple of a person's pace — and NOT derived from size.
## Giants keeps a person's pace at eight times the size (which is what
## makes a giant feel like a giant from the inside); Tag's It is twice the
## size and twice as quick. One knob could not have served both.
func set_speed(id: String, scale: float) -> void:
	if not multiplayer.is_server():
		return
	world.cl_speed.rpc(id, scale)

## WHICH SIDE SOMEBODY IS ON, changed where they stand rather than by
## sending them home.
##
## MatchDirector.stand_again already switches sides, but it is a stand-UP:
## it teleports you to your side's start and hands you the kit. Being
## tagged has to move you across without moving you an inch.
func set_team(id: String, team: int) -> void:
	if not multiplayer.is_server() or not world.roster().has(id):
		return
	if int(world.roster()[id].get("team", -1)) == team:
		return
	Game.roster[id].team = team
	Game.cl_roster.rpc(Game.roster)

## A SWING THAT LANDED, wherever it came from — a person's sword, a
## person's hand, or a computer player closing the last two blocks.
##
## Shared on purpose. The computer players used to call `match_hurt`
## themselves, which was fine while every melee weapon in the game was the
## sword and meant exactly one thing; the moment a mode can say that a
## swing TAGS somebody instead, two code paths means the bots carry on
## playing last week's game. Returns whether the swing did anything.
func melee_hit(attacker: String, target_id: String, attacker_pos: Vector3) -> bool:
	# WHAT A SWING MEANS IS THE MODE'S. It has killed outright since there
	# was a sword and still does everywhere that does not say otherwise —
	# but Tag's one weapon is a hand, and a hand that took hearts off
	# somebody would be a sword with a friendlier name.
	match world.rules.on_melee(world, attacker, target_id):
		"none":
			return false
		"tag":
			return true
	world.battle.hurt(target_id, world.MATCH_HP, attacker_pos, attacker)
	return true

# ---- hearts ------------------------------------------------------------

## HOW MANY HEARTS A ROUND STARTS YOU WITH: people, computer players, and
## anyone the world menu has set by hand (id -> hearts).
##
## Here rather than on the world because hearts are a property of a BODY,
## and since Giants scales them with its size they are not even a fixed
## one — `max_hp` reads the size two lines below where the size is kept.
var hearts_people := 0
var hearts_bots := 0
var hearts_override: Dictionary = {}

## THE CLIENT'S COPY: what each player has, and the bar it is out of.
## Written only by cl_hearts. They are a pair and are kept as one — a
## count without its bar cannot be drawn, since how many hearts to light
## is the fraction of one over the other (Player.hearts_shown).
var hearts: Dictionary = {}
var hearts_max: Dictionary = {}

func _ready() -> void:
	hearts_people = world.MATCH_HP
	hearts_bots = world.MATCH_HP

## What the settings say, then whatever the MODE says about it — which is
## where a giant's hearts come from. Clamped to the ceiling rather than to
## MATCH_HP, or a mode that hands out more than eight would quietly have
## them taken away again.
func max_hp(id: String) -> int:
	var base := hearts_bots if bool(world.roster().get(id, {}).get("bot", false)) \
		else hearts_people
	if hearts_override.has(id):
		base = int(hearts_override[id])
	return clampi(world.rules.max_hp(world, id, base), 1, world.MAX_HP_CEILING)

## HEARTS AND TEAM COLOUR OVER EVERY HEAD, which is a thing this node can
## do because it is a thing this node knows: the count, the bar it is out
## of, and which side everybody is on are all here.
func refresh_overheads() -> void:
	if world.players == null:
		return
	# NOTHING OVER ANYBODY in a game with no knockouts. `friendly` already
	# means "no target over this one", which is what a game where nobody
	# can be hurt wants for every player in it, not only your own side.
	var no_hearts: bool = not world.client_rules.has_knockouts() \
		and not world.survival_active
	var local_teams: Dictionary = {}
	for lid in Game.local_player_ids():
		local_teams[int(Game.roster.get(lid, {}).get("team", -1))] = true
	for child in world.players.get_children():
		if not (child is Player):
			continue
		var team := int(Game.roster.get(child.player_id, {}).get("team", -1))
		var team_color: Color = WorldNode.TEAM_COLORS[team] if team >= 0 \
			and team < WorldNode.TEAM_COLORS.size() else Color(1, 1, 1)
		# The bar as well as the count — see Player.hearts_shown.
		child.refresh_overhead(int(hearts.get(child.player_id, 8)),
			team_color, world.client_downed.has(child.player_id),
			no_hearts or (team >= 0 and local_teams.has(team)),
			int(hearts_max.get(child.player_id, Player.HEART_CELLS)))

# ---- the client's side -------------------------------------------------

## Arrived from the server. Puts the number on the body it belongs to, and
## keeps a copy for anybody spawned later.
func apply_size(id: String, size: float) -> void:
	sizes[id] = size
	for child in world.players.get_children():
		if child is Player and child.player_id == id:
			child.set_body_size(size)

func apply_speed(id: String, scale: float) -> void:
	for child in world.players.get_children():
		if child is Player and child.player_id == id:
			child.speed_scale = scale
