extends Node
## WORLD_GHOST_TEST=1: what does a knocked-out team actually look like?
##
##   WORLD_ROLE=client WORLD_GHOST_TEST=1 WORLD_AUTOTEST=1 \
##     WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --headless --path game
##
## Losing your flag in last flag standing puts your whole side OUT: they
## cannot be hurt, cannot shoot, and are supposed to be invisible to
## everybody still playing. Reported from a real game, what actually
## happened was "the remaining player on that team stopped shooting and
## just ran around, I couldn't kill them, like they went into some weird
## mode" — which is every one of those rules working except the one that
## makes them disappear.
##
## A player who is out, visible and moving is indistinguishable from a
## broken opponent: you shoot it and nothing happens. That is three
## separate facts about one body, and no single side of the wire holds all
## three — the server knows who is out, the CLIENT knows what is drawn.
## So this asks the client, which is the only place the question can be
## answered.
##
## It reports rather than judging, except for the one thing that is never
## right: out, visible, and moving.

const START_AFTER := 8.0
const EVERY := 3.0

var _t := 0.0
var _said := 0.0
var _was: Dictionary = {}
var _ghosts := 0

func _ready() -> void:
	print("GHOST: probe armed")

func _physics_process(delta: float) -> void:
	_t += delta
	if _t < START_AFTER:
		return
	var world: WorldNode = Game.world
	if world == null or world.players == null:
		return
	if _t - _said < EVERY:
		return
	_said = _t
	var out_n := 0
	var shown := 0
	var moving := 0
	var worst := ""
	for child in world.players.get_children():
		if not (child is Player):
			continue
		var who: String = child.player_id
		if not world.out_ids.has(who):
			_was.erase(who)
			continue
		# NOT YOURSELF. Being out turns a PERSON into a spectator: they
		# fly, they follow a team-mate, they talk them onto the spot where
		# they went down — that is the whole design, and it is why being
		# out does not simply end your evening. Counting your own
		# spectating as a body loose on the field reports the one case
		# that is working as the failure. The question is about everybody
		# ELSE's body.
		if child.is_local:
			continue
		out_n += 1
		var moved: float = 0.0
		if _was.has(who):
			moved = Vector3(_was[who]).distance_to(child.position)
		_was[who] = child.position
		if child.visible:
			shown += 1
		if moved > 1.0:
			moving += 1
		# DRAWN AND MOVING is the unkillable opponent, and either half on
		# its own is still wrong. Being drawn at all is the visible bug.
		# Still walking the map is the one underneath it: a body that
		# cannot be hurt, cannot shoot and cannot take anything has no
		# business anywhere near the fight, and every step it takes is a
		# position broadcast and one more chance for something to fail to
		# hide it.
		if child.visible or moved > 1.0:
			_ghosts += 1
			worst = "%s (%s, moved %.1f)" % [
				str(Game.roster.get(who, {}).get("name", who)),
				"DRAWN" if child.visible else "hidden", moved]
	if out_n == 0:
		print("GHOST: t=%.0fs nobody is out yet" % _t)
		return
	print("GHOST: t=%.0fs out=%d drawn=%d moving=%d | %s%s"
		% [_t, out_n, shown, moving,
			"ok   the out are put away" if _ghosts == 0
				else "FAIL %d sightings of a body still in the round" % _ghosts,
			"" if worst.is_empty() else " | worst: " + worst])
