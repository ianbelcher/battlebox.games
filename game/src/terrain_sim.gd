class_name TerrainSim
extends Node
## Everything the world does to itself while nobody is looking: water
## finding its level, fire spreading and burning out, saplings becoming
## trees, and charges going off. Server-side only, at World/Terrain.
##
## Each of these runs on its own accumulator rather than every frame,
## because they are all cellular: water at ~3 Hz, fire at ~1.2 Hz, growth
## every 7 seconds. Running them per-frame would spend the server's only
## thread on ponds.
##
## Nothing here is an @rpc. Everything it changes goes out through the
## world's cl_edit/cl_edits/cl_batch, so a client learns about a flooded
## crater exactly the way it learns about somebody placing a block.

## The world being simulated.

var world: WorldNode = null


var _saplings: Array = []            # [{pos: Vector3i, at_msec: int}]

var _bombs: Array = []               # [{pos: Vector3i, at_msec: int}]

var _rockets: Array = []             # [{pos: Vector3i, at_msec: int}]

var _was_night := false

var _water_accum := 0.0

var _fire_accum := 0.0

var _boom_armed: Dictionary = {}   # Vector3i -> msec it becomes live

## Fire: burning cells spread through flammable blocks, gutter out on
## steel/stone, and singe players and Grumps standing in them.

var _fires: Dictionary = {}   # Vector3i -> expiry msec

var _burn_hurt_ms: Dictionary = {}  # player id -> next hurt msec

var _holes: Array = []

func tick_smoke() -> void:
	if world._smoke_marker.is_empty():
		return
	if Time.get_ticks_msec() >= int(world._smoke_marker.get("until", 0)):
		world._smoke_marker.clear()
		world.cl_smoke_clear.rpc()

## Anyone stood on an armed Boom Block sets it off, now.
func tick_boom_traps() -> void:
	if _boom_armed.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id: String in world.player_state.keys():
		if world.downed_ids.has(id) or world.out_ids.has(id):
			continue
		var at: Vector3 = world.player_state[id].get("pos", Vector3.INF)
		if at == Vector3.INF:
			continue
		var under := Vector3i(floori(at.x), floori(at.y) - 1, floori(at.z))
		if not _boom_armed.has(under):
			continue
		if now < int(_boom_armed[under]):
			continue
		if world.store.get_block(under) != Blocks.BOOM:
			_boom_armed.erase(under)
			continue
		_boom_armed.erase(under)
		explode(under)

func tick_bombs() -> void:
	var now := Time.get_ticks_msec()
	var pending: Array = []
	for entry: Dictionary in _bombs:
		if now < entry.at_msec:
			pending.append(entry)
		elif world.store.get_block(entry.pos) == Blocks.BOOM:  # not defused by digging
			explode(entry.pos)
	_bombs = pending
	pending = []
	for entry: Dictionary in _rockets:
		if now < entry.at_msec:
			pending.append(entry)
		elif world.store.get_block(entry.pos) == Blocks.FIREWORK:
			world.store.set_block(entry.pos, Blocks.AIR)
			world.cl_batch.rpc([entry.pos], Blocks.AIR)
			world.cl_firework_fx.rpc(entry.pos)
	_rockets = pending

func explode(origin: Vector3i) -> void:
	# Every Boom Block CONNECTED to this one goes up together: n charges make
	# one blast with ~cbrt(n) times the radius. Unconnected ones nearby still
	# chain with short fuses.
	var connected: Dictionary = {origin: true}
	var frontier: Array = [origin]
	while not frontier.is_empty() and connected.size() < 64:
		var at: Vector3i = frontier.pop_back()
		for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
				Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var next: Vector3i = at + off
			if not connected.has(next) and world.store.get_block(next) == Blocks.BOOM:
				connected[next] = true
				frontier.append(next)
	var center := Vector3.ZERO
	for pos: Vector3i in connected.keys():
		world.store.set_block(pos, Blocks.AIR)
		center += Vector3(pos)
		# A merged charge can't also be a pending fuse.
		for i in range(_bombs.size() - 1, -1, -1):
			if _bombs[i].pos == pos:
				_bombs.remove_at(i)
	center /= connected.size()
	var radius := world.BOOM_RADIUS * pow(connected.size(), 0.34)
	blast(Vector3i(center.round()), radius, connected.keys())

## Shave a crater's lip until you can walk out of it.
##
## A blast carves a SPHERE, and a sphere meets the ground almost
## vertically at its rim — so the outer ring of every crater was a wall
## one to three blocks high. Land in one mid-fight and you were simply
## stuck in a pit while somebody shot down at you, which is not a game.
##
## So: measure the surface height of every column in and just around the
## crater, then relax it until no column stands more than ONE block above
## its lowest neighbour. The result is a shallow bowl with a walkable
## slope all the way round. Digging a shaft straight down under your own
## feet is still your own business — this only touches the footprint of
## an explosion.
func walk_out(origin: Vector3i, radius: float) -> void:
	var cut := world.store.carve_exit_ramp(origin, radius)
	if not cut.is_empty():
		world.cl_batch.rpc(cut, Blocks.AIR)

func blast(origin: Vector3i, radius: float, pre_cleared: Array, impact := Vector3i(0, -999, 0)) -> void:
	var cleared: Array = pre_cleared.duplicate()
	var reach := int(ceil(radius))
	for dy in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if Vector3(dx, dy, dz).length() > radius:
					continue
				var pos := origin + Vector3i(dx, dy, dz)
				var block := world.store.get_block(pos)
				if block == Blocks.AIR or Blocks.is_liquid(block) or not world.can_carve(pos, block):
					continue
				# Material tiers: stone only breaks near the heart of the
				# blast, steel only on a direct hit, diamond never.
				var tier := Blocks.hardness(block)
				if tier >= 4:
					continue
				if tier == 3 and pos != impact:
					continue
				if tier == 2 and Vector3(dx, dy, dz).length() > radius * 0.65 and pos != impact:
					continue
				# Chain reaction: other boom blocks in the blast go off too.
				if block == Blocks.BOOM and pos != origin:
					var already := false
					for entry: Dictionary in _bombs:
						if entry.pos == pos:
							already = true
					if not already:
						_bombs.append({"pos": pos, "at_msec": Time.get_ticks_msec() + 350})
					continue
				world.store.set_block(pos, Blocks.AIR)
				cleared.append(pos)
	world.cl_batch.rpc(cleared, Blocks.AIR)
	# Nothing moved, nothing to smooth — skip the heightmap pass for shots
	# that hit air or bounced off diamond.
	if not cleared.is_empty():
		walk_out(origin, radius)
	# Scorch the crater floor.
	var charred: Array = []
	for pos: Vector3i in cleared:
		var below: Vector3i = pos + Vector3i(0, -1, 0)
		var floor_block := world.store.get_block(below)
		if floor_block != Blocks.AIR and not Blocks.is_liquid(floor_block) \
				and Blocks.hardness(floor_block) < 2 and world.can_carve(below, floor_block) \
				and WorldGen.hash01(below.x, below.z, below.y) < 0.6:
			world.store.set_block(below, Blocks.CHARRED)
			charred.append(below)
	if not charred.is_empty():
		world.cl_batch.rpc(charred, Blocks.CHARRED)
	# Explosions start fires in whatever flammable stuff rings the crater.
	var lit: Array = []
	for pos: Vector3i in cleared:
		for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
			var next: Vector3i = pos + off
			if Blocks.is_flammable(world.store.get_block(next)) and not _fires.has(next) \
					and _fires.size() < 120 and WorldGen.hash01(next.x, next.z, next.y) < 0.35:
				world.store.set_block(next, Blocks.FIRE)
				_fires[next] = Time.get_ticks_msec() + randi_range(5000, 11000)
				lit.append(next)
	if not lit.is_empty():
		world.cl_batch.rpc(lit, Blocks.FIRE)
	# The blast knows how big it was; the effect should too. Without this
	# a Little Shooter pellet and a Big Shooter shell threw exactly the
	# same shower of sparks, which is the one moment the difference
	# between those two weapons ought to be unmissable.
	world.cl_boom_fx.rpc(origin, radius)
	disturb_water(cleared)

func ignite_at(cell: Vector3i) -> void:
	var placed: Array = []
	for off in [Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 0, 0),
			Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var pos: Vector3i = cell + off
		var block := world.store.get_block(pos)
		if (block == Blocks.AIR or Blocks.is_flammable(block)) and _fires.size() < 120:
			world.store.set_block(pos, Blocks.FIRE)
			_fires[pos] = Time.get_ticks_msec() + randi_range(5000, 10000)
			placed.append(pos)
	if not placed.is_empty():
		world.cl_batch.rpc(placed, Blocks.FIRE)

func tick_fire() -> void:
	if _fires.is_empty():
		return
	var now := Time.get_ticks_msec()
	var out: Array = []
	var lit: Array = []
	for pos: Vector3i in _fires.keys():
		if now > int(_fires[pos]):
			_fires.erase(pos)
			if world.store.get_block(pos) == Blocks.FIRE:
				world.store.set_block(pos, Blocks.AIR)
				out.append(pos)
			continue
		# Spread into flammable neighbors (steel and stone never catch).
		if randf() < 0.55 and _fires.size() < 120:
			var offs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
				Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
			var off: Vector3i = offs[randi() % offs.size()]
			var next: Vector3i = pos + off
			if Blocks.is_flammable(world.store.get_block(next)) and not _fires.has(next):
				world.store.set_block(next, Blocks.FIRE)
				_fires[next] = now + randi_range(5000, 11000)
				lit.append(next)
	if not out.is_empty():
		world.cl_batch.rpc(out, Blocks.AIR)
	if not lit.is_empty():
		world.cl_batch.rpc(lit, Blocks.FIRE)
	# Ouch: players and Grumps in the flames.
	for id: String in world.player_state.keys():
		if now < int(_burn_hurt_ms.get(id, 0)):
			continue
		var ppos: Vector3 = world.player_state[id].pos
		var cell := Vector3i(floori(ppos.x), floori(ppos.y + 0.3), floori(ppos.z))
		if _fires.has(cell) or _fires.has(cell + Vector3i(0, -1, 0)) or _fires.has(cell + Vector3i(0, 1, 0)):
			_burn_hurt_ms[id] = now + 1500
			world.cl_bonk.rpc(id, ppos + Vector3(0.4, -0.5, 0.4))
			if world.survival_active and not world._downed.has(id):
				var state: Dictionary = world.player_state[id]
				state.hp = int(state.get("hp", 5)) - 1
				world.cl_hearts.rpc(id, state.hp)
				if state.hp <= 0:
					world._downed[id] = true
					world.cl_downed.rpc(id)
	for monster_id: int in world.monsters_by_id.keys().duplicate():
		var mcell := Vector3i(world.monsters_by_id[monster_id].pos.floor())
		if _fires.has(mcell):
			world.monsters_by_id[monster_id].hp = int(world.monsters_by_id[monster_id].hp) - 1
			var dead: bool = world.monsters_by_id[monster_id].hp <= 0
			if dead:
				world.monsters_by_id.erase(monster_id)
				world.survival._bonked_count += 1
			world.cl_zap_hit.rpc(monster_id, dead)

func disturb_water(removed_cells: Array) -> void:
	for cell in removed_cells:
		if cell is Vector3i and _holes.size() < 400:
			# Spread 0: a dug hole leaks, it doesn't spill across the floor.
			_holes.append({"pos": cell, "spread": 0})

func tick_water() -> void:
	if _holes.is_empty():
		return
	var filled: Array = []
	var next_holes: Array = []
	var budget := 48
	while not _holes.is_empty() and budget > 0:
		var entry = _holes.pop_front()
		var hole: Vector3i = entry.pos
		var spread: int = int(entry.get("spread", 0))
		if world.store.get_block(hole) != Blocks.AIR:
			continue
		var wet := false
		for off in [Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
				Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var neighbor_block := world.store.get_block(hole + off)
			if neighbor_block == Blocks.WATER:
				wet = true
				break
		if not wet:
			continue
		budget -= 1
		world.store.set_block(hole, Blocks.WATER)
		filled.append(hole)
		# Nothing underneath? Fall, and only fall. The cell below carries a
		# full spread budget, which it spends only if it lands on something.
		var below: Vector3i = hole + Vector3i(0, -1, 0)
		if world.store.get_block(below) == Blocks.AIR:
			if next_holes.size() < 200:
				next_holes.append({"pos": below, "spread": world.WATER_SPREAD})
		elif spread > 0:
			# Landed: puddle outwards, a block less reach each step.
			for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
					Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var next: Vector3i = hole + off
				if world.store.get_block(next) == Blocks.AIR \
						and next_holes.size() < 200:
					next_holes.append({"pos": next, "spread": spread - 1})
	_holes.append_array(next_holes)
	if not filled.is_empty():
		world.cl_batch.rpc(filled, Blocks.WATER)

## Sponges drink every liquid within reach the moment they're placed.
func drain(origin: Vector3i) -> void:
	var cleared: Array = []
	for dy in range(-4, 5):
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				if Vector3(dx, dy, dz).length() > 3.8:
					continue
				var pos := origin + Vector3i(dx, dy, dz)
				if Blocks.is_liquid(world.store.get_block(pos)):
					world.store.set_block(pos, Blocks.AIR)
					cleared.append(pos)
	if not cleared.is_empty():
		world.cl_batch.rpc(cleared, Blocks.AIR)

## Saplings grow into little trees after a couple of minutes.
func tick_growth() -> void:
	var now := Time.get_ticks_msec()
	var remaining: Array = []
	for entry: Dictionary in _saplings:
		if now - entry.at_msec < world.growth_msec():
			remaining.append(entry)
			continue
		var base: Vector3i = entry.pos
		if world.store.get_block(base) != Blocks.SAPLING:
			continue  # someone dug it up
		grow_tree(base)
	_saplings = remaining

func grow_tree(base: Vector3i) -> void:
	var trunk := 3 + int(WorldGen.hash01(base.x, base.z, 77) * 3.0)
	for i in trunk:
		place(base + Vector3i(0, i, 0), Blocks.LOG)
	var top := base + Vector3i(0, trunk, 0)
	for dy in range(-2, 3):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if Vector3(dx, dy * 1.4, dz).length() > 2.45:
					continue
				var pos := top + Vector3i(dx, dy, dz)
				if world.store.get_block(pos) == Blocks.AIR:
					place(pos, Blocks.LEAVES)

func place(pos: Vector3i, block: int) -> void:
	world.store.set_block(pos, block)
	world.cl_edit.rpc(pos, block, "")

## At dawn, fresh flowers pop up near wherever people are playing.
func dawn_check() -> void:
	var night := world.clock > 0.78 or world.clock < 0.22
	if _was_night and not night:
		for state: Dictionary in world.player_state.values():
			for attempt in 8:
				var pos: Vector3 = state.pos
				var wx := int(pos.x) + int(WorldGen.hash01(attempt, int(pos.x), 91) * 40.0) - 20
				var wz := int(pos.z) + int(WorldGen.hash01(attempt, int(pos.z), 92) * 40.0) - 20
				var y := world.store.surface_y(wx, wz)
				var ground := world.store.get_block(Vector3i(wx, y, wz))
				var above := world.store.get_block(Vector3i(wx, y + 1, wz))
				if ground == Blocks.GRASS and above == Blocks.AIR and attempt % 2 == 0:
					var flowers := [Blocks.FLOWER_RED, Blocks.FLOWER_YELLOW, Blocks.FLOWER_PINK]
					place(Vector3i(wx, y + 1, wz),
						flowers[int(WorldGen.hash01(wx, wz, 93) * 3.0)])
	_was_night = night
