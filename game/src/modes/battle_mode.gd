class_name BattleMode
extends GameMode
## BATTLE ROYALE: everybody drops, a storm closes in, the last side
## standing wins.
##
## THE STORM LIVES HERE. Where it closes to, how fast, what it does to
## anybody outside it and to the ground just beyond it — all of it is
## this file's. The platform has the picture (world.storm_radius and
## storm_center, which every client draws) and the primitives (hearts,
## elimination, crumbling ground); this is the game played with them.

func _init() -> void:
	key = "battle"
	label = "Battle royale"
	note = "Last one standing wins the round"

func has_rounds() -> bool:
	return true

func has_clock() -> bool:
	return true

## When each player may next lose a heart to the storm, and when the
## ground next crumbles. Round state; reset at the start.
var _hurt_ms: Dictionary = {}
var _next_bite_ms := 0
var _stage := ""

## The circle closes on a RANDOM spot each battle, and the wall starts
## beyond the arena edge so no red is visible at the drop.
func on_round_start(world: Node) -> void:
	_hurt_ms.clear()
	_next_bite_ms = 0
	_stage = ""
	var angle := randf() * TAU
	var dist := randf() * float(world.battle_size) * 0.22
	world.storm_center = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	world.storm_radius = _start_radius(world)

## Big enough that the wall starts beyond every corner of the arena from
## wherever this battle's centre landed.
func _start_radius(world: Node) -> float:
	return float(world.battle_size) * 0.75 \
		+ Vector2(world.storm_center.x, world.storm_center.z).length()

## The storm's length is the round's. Unlimited is a clock that never
## reaches the storm: it never closes, and the round only ends when one
## side is left.
func round_seconds(world: Node) -> float:
	if float(world.storm_minutes) >= 59.0:
		return 1.0e9
	return float(world.storm_minutes) * 60.0

func tick(world: Node, _delta: float, seconds_left: float) -> void:
	var storm := StormClock.at(seconds_left, float(world.storm_minutes) * 60.0,
		_start_radius(world))
	world.storm_radius = float(storm.radius)
	world.cl_storm.rpc(world.storm_radius, world.storm_center, float(storm.seconds))
	_say_stage(world)
	if world.storm_radius >= 0.0:
		_hurt_outside(world)
		var now := Time.get_ticks_msec()
		if now >= _next_bite_ms:
			_next_bite_ms = now + 500
			world.terrain.crumble_ring(world.storm_center, world.storm_radius, 6)

func winner(_world: Node, teams_alive: Array) -> int:
	if teams_alive.size() > 1:
		return CONTINUE
	return int(teams_alive[0]) if teams_alive.size() == 1 else -1

## Outside the wall you are ON THE CLOCK. A short grace band, then
## damage that speeds up the further out you are: matches used to end by
## everyone standing in the middle waiting for the storm to get round to
## it. No knockback from the storm: pushing players while they are
## already outside fed back into more damage and once launched a player
## 142 km off the map.
func _hurt_outside(world: Node) -> void:
	var now := Time.get_ticks_msec()
	for id: String in world.match_alive.keys():
		var state: Dictionary = world.player_state.get(id, {})
		if state.is_empty() or now < int(_hurt_ms.get(id, 0)):
			continue
		var pos: Vector3 = state.pos
		var out: float = Vector2(pos.x - world.storm_center.x,
			pos.z - world.storm_center.z).length() - float(world.storm_radius)
		# A short grace band outside the wall — until the wall has closed
		# to nothing, when there is no inside left to be graced by.
		var grace := 2.0 if world.storm_radius > 0.0 else -1.0
		if out <= grace:
			continue
		# 1.1s a heart at the edge, down to 0.3s deep out — eight hearts
		# is about nine seconds at the rim, under three if you ignore it.
		var bite := clampf(1.1 - out / 40.0, 0.3, 1.1)
		_hurt_ms[id] = now + int(bite * 1000.0)
		state.hp = int(state.get("hp", world.MATCH_HP)) - 1
		world.send_hearts(id)
		if state.hp > 0:
			continue
		if not world.downed_ids.has(id):
			world.battle.eliminate(id)
		elif state.hp <= -world.MATCH_HP:
			# ON THE FLOOR IN THE STORM. Being knocked out is not a
			# countdown anywhere else — you wait for a team-mate — but
			# nobody is coming out here, and a downed player the storm
			# could not finish was a round that could not end.
			world.battle.put_out(id)

## One line on the server's stdout as the wall changes what it is doing,
## so a log says when the last stand began and when the round was shut.
func _say_stage(world: Node) -> void:
	var stage := "none"
	if world.storm_radius < 0.0:
		stage = "none"
	elif world.storm_radius == 0.0:
		stage = "shut"
	elif world.storm_radius <= StormClock.HOLD_RADIUS:
		stage = "last stand"
	else:
		stage = "closing"
	if stage == _stage:
		return
	_stage = stage
	match stage:
		"closing":
			print("STORM: closing in, %d still in it" % world.match_alive.size())
		"last stand":
			print("STORM: last stand — the wall holds at %d for %ds, %d still in it"
				% [int(StormClock.HOLD_RADIUS), int(StormClock.HOLD_SECONDS),
					world.match_alive.size()])
		"shut":
			print("STORM: shut, %d still in it and burning" % world.match_alive.size())
