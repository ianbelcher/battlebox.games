class_name CritterDirector
extends Node
## The animals: how many the world should hold, where they are allowed to
## live, and where they wander next. Server-side only, at World/Critters.
##
## The server simulates coarse positions at ~3 Hz and broadcasts them;
## critter_view.gd on each client is what makes them glide, bob and flap
## between those updates. Sending 3 Hz and interpolating is the whole
## reason a world can hold this many of them.

## The world these animals live in.

var world: WorldNode = null


var critters: Dictionary = {}       # id -> {kind, pos, target, speed, think}

var _next_id := 1

## How many critters the server is simulating.
func count() -> int:
	return critters.size()

func tick() -> void:
	world.survival.tick()
	world.survival.tick_crates()
	var player_positions: Array = []
	for state: Dictionary in world.player_state.values():
		player_positions.append(state.pos)
	if player_positions.is_empty():
		if not critters.is_empty():
			critters.clear()
		return
	var night := world.clock > 0.78 or world.clock < 0.22
	# Cull the far and the out-of-season.
	for id: int in critters.keys().duplicate():
		var critter: Dictionary = critters[id]
		var near := false
		for pos: Vector3 in player_positions:
			if pos.distance_to(critter.pos) < 60.0:
				near = true
				break
		if not near or (critter.kind == CritterView.FIREFLY and not night):
			critters.erase(id)
	# Keep the population up around each player, but never more than the
	# world can carry. A 50-block world was getting the same 56 animals a
	# 350-block one did, which on that much ground is a zoo.
	if critters.size() < cap_for(player_positions.size()):
		var anchor: Vector3 = player_positions[randi() % player_positions.size()]
		try_spawn(anchor, night)
	# Wander + flee.
	for id: int in critters.keys():
		_move_critter(critters[id], player_positions)
	# Broadcast compact state.
	var payload: Array = []
	for id: int in critters.keys():
		var critter: Dictionary = critters[id]
		payload.append([id, critter.kind, critter.pos])
	world.cl_critters.rpc(payload)

## Coarse biome patches (~112 blocks across, fixed per world seed) so the
## island reads as REGIONS — a farm valley here, deep forest over there,
## jungle beyond it and wild country that claims nothing — instead
## of every animal everywhere. Which creatures suit which biome is set in
## src/creatures.gd, not here.
func biome_at(wx: int, wz: int) -> String:
	var patch_x := floori(float(wx) / 112.0)
	var patch_z := floori(float(wz) / 112.0)
	var roll := WorldGen.hash01(patch_x, patch_z, 4242)
	if roll < 0.30:
		return Creatures.FOREST
	if roll < 0.56:
		return Creatures.FARM
	if roll < 0.78:
		return Creatures.JUNGLE
	return Creatures.LAND  # wild country, nothing claims it

## How many animals this world should hold: per-player as before, but
## capped by the AREA of the slab so small worlds stay calm. Roughly one
## animal per 900 blocks of ground — a 50-block world tops out at a
## handful, a 350-block one at the old maximum.
func cap_for(player_count: int) -> int:
	var area := float(world.store.world_size) * float(world.store.world_size)
	var by_area := int(area / 900.0)
	return clampi(mini(world.CRITTERS_PER_PLAYER * player_count, by_area), 3,
		world.MAX_CRITTERS)

func try_spawn(anchor: Vector3, night: bool) -> void:
	var angle := randf() * TAU
	var dist := randf_range(10.0, 26.0)
	var wx := int(anchor.x + cos(angle) * dist)
	var wz := int(anchor.z + sin(angle) * dist)
	if not world.store.inside_world(wx, wz):
		return
	var y := world.store.surface_y(wx, wz)
	if y <= 1 or y >= WorldGen.CHUNK_H - 4:
		return
	var ground := world.store.get_block(Vector3i(wx, y, wz))
	var kind := -1
	# Registry creatures get first refusal: add or retire them in
	# src/creatures.gd and the world follows — nothing here needs touching.
	var habitat := biome_at(wx, wz)
	if ground == Blocks.WATER:
		habitat = Creatures.WATER
	elif ground == Blocks.SAND:
		habitat = Creatures.SAND
	elif ground == Blocks.SNOW:
		habitat = Creatures.SNOW
	var rolled := Creatures.roll(habitat)
	if rolled >= 0:
		kind = rolled
	elif WorldGen.hash01(wx, wz, 500) < 0.15:
		kind = CritterView.BIRD
	elif ground == Blocks.WATER:
		kind = CritterView.DUCK
	elif ground == Blocks.SAND:
		kind = CritterView.CRAB
	elif ground == Blocks.SNOW or (ground == Blocks.STONE and y > WorldGen.SEA_LEVEL + 14):
		kind = CritterView.PENGUIN
	elif ground == Blocks.GRASS:
		if night:
			kind = CritterView.FIREFLY if randf() < 0.6 else CritterView.BUNNY
		elif y <= WorldGen.SEA_LEVEL + 2 and randf() < 0.35:
			kind = CritterView.FROG
		else:
			var roll := randf()
			if roll < 0.28:
				kind = CritterView.SHEEP
			elif roll < 0.48:
				kind = CritterView.BUNNY
			elif roll < 0.64:
				kind = CritterView.CHICKEN
			elif roll < 0.78:
				kind = CritterView.DEER
			else:
				kind = CritterView.BUTTERFLY
	if kind < 0:
		return
	var pos := Vector3(wx + 0.5, y + 1.0, wz + 0.5)
	critters[_next_id] = {
		"kind": kind, "pos": pos, "target": pos,
		"speed": Creatures.speed_of(kind),
		"think": 0.0,
	}
	_next_id += 1

func _move_critter(critter: Dictionary, player_positions: Array) -> void:
	var delta := 0.33
	var move_mode := Creatures.move_of(int(critter.kind))
	# The jungle python is modelled lying down and rotated, so any walking
	# at all looks wrong — it just rests on the ground where it spawned.
	if move_mode == Creatures.STILL:
		critter.pos.y = float(world.store.surface_y(floori(critter.pos.x),
			floori(critter.pos.z))) + 1.0
		return
	# Ground creatures settle onto whatever is under them EVERY tick, not
	# just while walking: shoot the block out from under an animal and it
	# falls instead of hanging in mid-air.
	if move_mode == Creatures.GROUND:
		var rest_y := float(world.store.surface_y(floori(critter.pos.x),
			floori(critter.pos.z))) + 1.0
		if critter.pos.y > rest_y:
			critter.pos.y = maxf(rest_y, critter.pos.y - 9.0 * delta)
		elif critter.pos.y < rest_y:
			critter.pos.y = rest_y  # a block grew underneath: pop out of it
	# Flee players who get too close (except butterflies, who don't care).
	if critter.kind != CritterView.BUTTERFLY:
		for pos: Vector3 in player_positions:
			if pos.distance_to(critter.pos) < 2.6:
				var away: Vector3 = (critter.pos - pos)
				away.y = 0
				critter.target = critter.pos + away.normalized() * 7.0
				critter.think = 3.0
				break
	# Fliers roam on their own terms — see _move_flier.
	if move_mode == Creatures.FLIER:
		_move_flier(critter, delta)
		return
	critter.think -= delta
	if critter.think <= 0.0:
		critter.think = randf_range(2.0, 5.0)
		var angle := randf() * TAU
		# Clamped, or a wander that happens to point outwards walks the
		# animal off the edge of the slab and into the void.
		critter.target = world.store.clamp_inside(critter.pos
			+ Vector3(cos(angle), 0, sin(angle)) * randf_range(2.0, 8.0))
	var to_target: Vector3 = critter.target - critter.pos
	to_target.y = 0
	if to_target.length() > 0.3:
		var speed: float = critter.speed
		var step: Vector3 = to_target.limit_length(speed * delta)
		var next: Vector3 = critter.pos + step
		var y := world.store.surface_y(floori(next.x), floori(next.z))
		var ground := world.store.get_block(Vector3i(floori(next.x), y, floori(next.z)))
		if move_mode == Creatures.SWIMMER:
			if ground != Blocks.WATER:
				critter.think = 0.0
				return
			next.y = float(y) + 0.9
		else:
			if ground == Blocks.WATER:
				critter.think = 0.0
				return
			# Climbing more than a block is a wall — but DROPPING is
			# always allowed, so anything stranded on a ledge or pillar
			# walks off the edge and falls instead of being stuck there.
			if float(y) + 1.0 - critter.pos.y > 1.3:
				critter.think = 0.0
				return
			next.y = maxf(float(y) + 1.0, critter.pos.y - 9.0 * delta)
		critter.pos = next

## Fliers cruise between far-apart waypoints and never ask the ground for
## permission to move. They used to share the walkers' 2-8 block wander and
## the walkers' veto rules, which is why pterodactyls never moved at all
## and the odd bird sat in one spot: a wander target that landed where the
## bird already was, or over ground it couldn't have stood on, pinned it
## there for good. The terrain now only sets a floor to stay above; the
## species' fly_height is still added on top by CritterView.
func _move_flier(critter: Dictionary, delta: float) -> void:
	critter.think -= delta
	if critter.think <= 0.0 or critter.pos.distance_to(critter.target) < 2.0:
		critter.think = randf_range(4.0, 9.0)
		var angle := randf() * TAU
		var spot: Vector3 = world.store.clamp_inside(critter.pos
			+ Vector3(cos(angle), 0, sin(angle)) * randf_range(14.0, 34.0), 6)
		spot.y = float(world.store.surface_y(floori(spot.x), floori(spot.z))) + 1.0 \
			+ randf_range(0.0, 5.0)
		critter.target = spot
	var step: Vector3 = (critter.target - critter.pos).limit_length(
		float(critter.speed) * delta)
	var next: Vector3 = critter.pos + step
	# Never fly into a hillside: keep a block of air under the wings.
	next.y = maxf(next.y,
		float(world.store.surface_y(floori(next.x), floori(next.z))) + 1.0)
	if OS.get_environment("WORLD_FLIER_DEBUG") == "1":
		print("FLIER kind=%d moved %.2f -> %v" % [int(critter.kind),
			critter.pos.distance_to(next), next])
	critter.pos = next
