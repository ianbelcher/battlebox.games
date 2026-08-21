class_name SurvivalDirector
extends Node
## The Grump raid, and the supply crates that both it and the battle use.
## Server-side only, at World/Survival.
##
## Grumps rise from low ground and water and walk at whoever is nearest.
## They can only step up ONE block, which is the whole design: a wall two
## blocks high actually works, so the forts the kids build are forts.

## The world under attack.

var world: WorldNode = null


var _next_monster_id := 1

var _started_ms := 0

var _wave_started_ms := 0

var _bonked_count := 0

var _next_crate_id := 1

func finish() -> void:
	var seconds := (Time.get_ticks_msec() - _started_ms) / 1000.0
	world.survival_active = false
	world.monsters_by_id.clear()
	world.cl_monsters.rpc([])
	world.cl_survival.rpc(false, seconds, _bonked_count)
	print("Survival over: %.0fs, %d bonked" % [seconds, _bonked_count])

func tick() -> void:
	if not world.survival_active and world.monsters_by_id.is_empty():
		return
	var now := Time.get_ticks_msec()
	# Escalate every 18s (raids only; whistled wild Grumps just roam).
	if world.survival_active and now - _wave_started_ms > 18_000:
		_wave_started_ms = now
		world.survival_wave += 1
		world.cl_wave.rpc(world.survival_wave)
	# Alive participants.
	var alive: Array = []
	for id: String in Game.roster.keys():
		if not world._downed.has(id) and world.player_state.has(id):
			alive.append(id)
	if alive.is_empty() or Game.roster.is_empty():
		if world.survival_active:
			finish()
		else:
			world.monsters_by_id.clear()
			world.cl_monsters.rpc([])
		return
	# Keep the horde growing.
	if world.survival_active:
		var cap := mini(4 + world.survival_wave * 2, 26)
		if world.monsters_by_id.size() < cap:
			spawn_monster(alive)
	# March.
	var speed := minf(1.5 + world.survival_wave * 0.06, 2.8) * 0.33
	var frozen_check := Time.get_ticks_msec()
	for monster_id: int in world.monsters_by_id.keys():
		var monster: Dictionary = world.monsters_by_id[monster_id]
		if frozen_check < int(monster.get("frozen_until", 0)):
			continue
		var target := _nearest_alive(monster.pos, alive)
		if target.is_empty():
			continue
		var target_pos: Vector3 = world.player_state[target].pos
		var step: Vector3 = target_pos - monster.pos
		step.y = 0
		if step.length() > 0.6:
			step = step.normalized() * speed
			# Grumps can't jump: they step up at most one block, so walls
			# and forts genuinely keep them out. They wade water fine.
			# Grumps scale walls and scuttle over roofs — height is no refuge.
			var attempt: Vector3 = monster.pos + step
			var floor_y := world.store.surface_y(floori(attempt.x), floori(attempt.z))
			var rise: float = float(floor_y) + 1.0 - monster.pos.y
			if rise > 0.9:
				attempt = monster.pos
				attempt.y += minf(rise, speed * 1.4)  # climbing
			else:
				attempt.y = float(floor_y) + 1.0
			monster.pos = attempt
		# Bonk!
		if now >= int(monster.next_bonk_ms) 				and Vector3(world.player_state[target].pos).distance_to(monster.pos) < 1.5:
			monster.next_bonk_ms = now + 1200
			var state: Dictionary = world.player_state[target]
			world.cl_bonk.rpc(target, monster.pos)
			if not world.survival_active:
				continue
			state.hp = int(state.get("hp", 5)) - 1
			world.cl_hearts.rpc(target, state.hp)
			if state.hp <= 0:
				world._downed[target] = true
				world.cl_downed.rpc(target)
	# Broadcast positions.
	var payload: Array = []
	for monster_id: int in world.monsters_by_id.keys():
		payload.append([monster_id, world.monsters_by_id[monster_id].pos])
	world.cl_monsters.rpc(payload)

func _nearest_alive(from: Vector3, alive: Array) -> String:
	var best := ""
	var best_dist := 1e9
	for id: String in alive:
		var dist: float = Vector3(world.player_state[id].pos).distance_to(from)
		if dist < best_dist:
			best_dist = dist
			best = id
	return best

## Grumps rise from low ground and water, never from up on the fort.
func spawn_monster(alive: Array) -> void:
	var anchor_id: String = alive[randi() % alive.size()]
	var anchor: Vector3 = world.player_state[anchor_id].pos
	var best_pos := Vector3.INF
	var best_score := -1e9
	for i in 14:
		var angle := randf() * TAU
		var dist := randf_range(16.0, 28.0)
		var wx := int(anchor.x + cos(angle) * dist)
		var wz := int(anchor.z + sin(angle) * dist)
		var y := world.store.surface_y(wx, wz)
		if y <= 1 or y >= WorldGen.CHUNK_H - 6:
			continue
		var score := anchor.y - float(y)
		if world.store.get_block(Vector3i(wx, y, wz)) == Blocks.WATER:
			score += 3.0
		if score > best_score:
			best_score = score
			best_pos = Vector3(wx + 0.5, y + 1.0, wz + 0.5)
	if best_pos == Vector3.INF or best_score < -4.0:
		return
	world.monsters_by_id[_next_monster_id] = {"pos": best_pos, "hp": 2 + world.survival_wave / 3,
		"next_bonk_ms": 0}
	_next_monster_id += 1

## Is this a spot a crate can actually sit on? The surface has to be
## SOLID GROUND — not a dome roof, not a ship's hull, not the lid of a
## bunker — and not perched high in the air above the local terrain.
## Space is full of things whose top face is 40 blocks up, and a crate
## placed on one reads as floating.
func crate_ground_ok(wx: int, wz: int, y: int) -> bool:
	if y <= 2 or y >= WorldGen.CHUNK_H - 6:
		return false
	if not world.store.inside_world(wx, wz):
		return false
	var under := world.store.get_block(Vector3i(wx, y, wz))
	if under == Blocks.WATER or Blocks.is_liquid(under):
		return false
	# Glass and steel are what the domes, ships and bunkers are made of.
	if under == Blocks.GLASS or under == Blocks.STEEL:
		return false
	if world.store.theme == "sky":
		return y > WorldGen.SEA_LEVEL + 6
	if world.store.theme == "space":
		# Must be the actual regolith, not something built on top of it:
		# anything more than a few blocks above the raw terrain height is
		# a roof.
		return y <= world.store.gen.height_at(wx, wz) + 2
	return true

## How much loot this world should be carrying.
##
## Rationed to the AREA of the map first — a big map needs more crates to
## feel stocked, and a small one is swamped by the same number — with a
## floor per player so two people on a huge map are not hunting a handful
## of crates between them. Capped by a density ceiling at the small end
## so a 50-block world does not become a car boot sale.
func crate_target() -> int:
	var area := float(world.store.world_size) * float(world.store.world_size)
	var want := maxi(int(area / 1100.0), Game.roster.size() * 4)
	want = mini(want, maxi(8, int(area / 200.0)))
	# Creative only needs a trickle. CAPTURE THE FLAG DOES NOT — it was
	# lumped in with creative by a `!= "battle"` test and got a quarter
	# ration, which on a big map is a scattering of crates nobody ever
	# trips over. It is a mode people fight in; it wants the same loot a
	# battle does.
	if world.game_mode == "creative":
		want = maxi(8, want / 4)
	return clampi(want, 8, 160)

func tick_crates() -> void:
	var positions: Array = []
	for state: Dictionary in world.player_state.values():
		positions.append(state.pos)
	if positions.is_empty():
		return
	# Loot settles onto the ground in creative too, not only mid-battle.
	world.battle._tick_crate_gravity()
	# Top back up to the SAME ration the battle started with. This used to
	# stop at 14 for the whole world, so once the opening loot had been
	# picked up — and the computer players are quick about it — a big map
	# was left with almost nothing on it.
	if world.crates_by_id.size() < crate_target():
		var anchor: Vector3 = positions[randi() % positions.size()]
		var angle := randf() * TAU
		var dist := randf_range(14.0, 60.0)
		var wx := int(anchor.x + cos(angle) * dist)
		var wz := int(anchor.z + sin(angle) * dist)
		var y := world.store.surface_y(wx, wz)
		if crate_ground_ok(wx, wz, y):
			# Rarer weapons show up less often.
			var pool := [1, 1, 1, 2, 9, 9, 11, 12, 12, 15, 15, 19]
			world.crates_by_id[_next_crate_id] = {"weapon": pool[randi() % pool.size()],
				"pos": Vector3(wx + 0.5, y + 1.0, wz + 0.5)}
			_next_crate_id += 1
			broadcast_crates()
	# Pickup by touch.
	for id: String in world.player_state.keys():
		var ppos: Vector3 = world.player_state[id].pos
		for crate_id: int in world.crates_by_id.keys():
			if ppos.distance_to(world.crates_by_id[crate_id].pos) < 1.6:
				var weapon: int = world.crates_by_id[crate_id].weapon
				world.crates_by_id.erase(crate_id)
				world.cl_crate_taken.rpc(id, weapon)
				if world.bots.roster.has(id):
					world.bots.roster[id].weapon = weapon
				broadcast_crates()
				break

func broadcast_crates() -> void:
	var payload: Array = []
	for crate_id: int in world.crates_by_id.keys():
		payload.append([crate_id, world.crates_by_id[crate_id].weapon, world.crates_by_id[crate_id].pos])
	world.cl_crates.rpc(payload)
