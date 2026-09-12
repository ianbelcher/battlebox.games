class_name KingHillMode
extends GameMode
## KING OF THE HILL: one mountain, a tide that only ever rises. Last side
## with somebody still on dry ground wins the round.
##
## THE TIDE LIVES HERE, the same way the storm lives in battle_mode.gd.
## The platform has the picture (world.water_level, which every client
## draws as a rising plane — see WorldNode._client_setup) and the
## primitives (hearts, elimination); this is the game played with them.
## There is no crumbling ground to go with it: the storm's is cosmetic
## erosion on top of a hazard that is purely a position check, and so is
## this one — see the note on TerrainSim.crumble_ring.

func _init() -> void:
	key = "king_hill"
	label = "King of the Hill"
	note = "The tide only rises — hold the high ground"

func has_rounds() -> bool:
	return true

func has_clock() -> bool:
	return true

## When each player may next lose a heart to the water. Round state;
## reset at the start, same shape as BattleMode's _hurt_ms.
var _hurt_ms: Dictionary = {}
var _start_level := 0.0
var _end_level := 0.0

func on_round_start(world: Node) -> void:
	_hurt_ms.clear()
	_start_level = float(WorldGen.SEA_LEVEL)
	# Six short of the true summit — a peak that floods completely
	# leaves nothing to be king OF. However the mountain came out, there
	# is always a last dry patch at the very top.
	_end_level = float(world.store.gen.height_at(0, 0)) - 6.0
	world.water_level = _start_level

## Unlimited is a clock that never reaches the flood: it never rises, and
## the round only ends when one side is left — same convention as
## BattleMode.round_seconds.
func round_seconds(world: Node) -> float:
	if float(world.storm_minutes) >= 59.0:
		return 1.0e9
	return float(world.storm_minutes) * 60.0

func tick(world: Node, _delta: float, seconds_left: float) -> void:
	var water := WaterClock.at(seconds_left, round_seconds(world),
		_start_level, _end_level)
	world.water_level = float(water.level)
	world.cl_water.rpc(world.water_level, float(water.seconds))
	_hurt_underwater(world)

func winner(_world: Node, teams_alive: Array) -> int:
	if teams_alive.size() > 1:
		return CONTINUE
	return int(teams_alive[0]) if teams_alive.size() == 1 else -1

## AT OR BELOW THE WATERLINE YOU ARE ON THE CLOCK, exactly like the storm:
## a short grace band (ankle-deep is not drowning), then damage that
## speeds up the deeper you are. No knockback, for the same reason the
## storm has none — pushing someone already underwater only ever made
## things worse for them, never better.
func _hurt_underwater(world: Node) -> void:
	var now := Time.get_ticks_msec()
	for id: String in world.match_alive.keys():
		var state: Dictionary = world.player_state.get(id, {})
		if state.is_empty() or now < int(_hurt_ms.get(id, 0)):
			continue
		var depth: float = world.water_level - float(state.pos.y)
		if depth <= 1.0:
			continue
		# 1.1s a heart ankle-deep, down to 0.3s fully under — the same
		# curve BattleMode uses for the storm, over ten blocks instead
		# of forty: there is far less "outside" to be gradually deep in.
		var bite := clampf(1.1 - depth / 10.0, 0.3, 1.1)
		_hurt_ms[id] = now + int(bite * 1000.0)
		state.hp = int(state.get("hp", world.MATCH_HP)) - 1
		world.send_hearts(id)
		if state.hp > 0:
			continue
		if not world.downed_ids.has(id):
			world.battle.eliminate(id)
		elif state.hp <= -world.MATCH_HP:
			# Face down in the water nobody is coming to pull them out
			# of — same call BattleMode makes for a downed player the
			# storm caught: a round that cannot end is worse than one
			# that ends unfairly for the one player it happens to.
			world.battle.put_out(id)
