extends SceneTree
## Two things about explosions, both of which have been got wrong before:
##
##   1. YOU CAN ALWAYS GET OUT of a crater.
##   2. AN EXPLOSION DESTROYS ROUGHLY WHAT IT LOOKS LIKE IT DESTROYS.
##
## The second is here because of how the first was fixed last time. That
## version relaxed the whole heightmap around the crater until no column
## stood more than a block above its neighbour — which does guarantee
## escape, by flattening a bowl two radii across. A big shooter round ate
## hundreds of blocks and left a smooth circular arena. So this test now
## measures the damage too, and fails if a shot removes far more than its
## own sphere.
##
##   godot --headless --path <game> \
##     --script res://tests/blast_walkout.gd
##
## Escape is checked the way a PLAYER would experience it: flood out from
## the crater floor across the heightmap, stepping up at most one block
## at a time (dropping any distance is free), and see whether the rim can
## be reached. That is the actual requirement — not "the ground is
## smooth", which is what the last version checked and which is why it
## accepted an answer that levelled the map.
##
## The test builds its own ground, so the result cannot depend on the
## terrain generator and a cave under the crater cannot be mistaken for a
## lip on it.

const RADII := [2.1, 4.0]        # medium shooter, big shooter
const GROUND_Y := 40
const PAD := 24
const SPACING := 56

## The way out may cost at most this much on top of the sphere itself.
## The ramp is a three-wide furrow a few blocks long, so this is roomy;
## the flattening version blew through it many times over.
const WASTE_ALLOWED := 1.6

var _failures := 0
var _checked := 0

func _initialize() -> void:
	var store := ChunkStore.new()   # _init() boots it from the environment
	var shapes := ["flat", "slope"]
	for ri in RADII.size():
		var radius: float = RADII[ri]
		for si in shapes.size():
			var shape: String = shapes[si]
			var at := Vector2i((si - 1) * SPACING + 20, (ri - 1) * SPACING + 20)
			_build(store, at, shape)
			var origin := Vector3i(at.x, GROUND_Y, at.y)
			var carved := _carve(store, origin, radius)
			var ramped: int = store.carve_exit_ramp(origin, radius).size()
			_check_escape(store, origin, radius, shape)
			_check_damage(radius, carved, ramped, shape)
	if _failures == 0:
		print("blast_walkout: PASS — %d craters, all escapable and all cheap"
			% _checked)
		quit(0)
	else:
		print("blast_walkout: FAIL — %d problems over %d craters"
			% [_failures, _checked])
		quit(1)

## Solid soil, either dead level or on a gradient.
func _build(store: ChunkStore, at: Vector2i, shape: String) -> void:
	for dz in range(-PAD, PAD + 1):
		for dx in range(-PAD, PAD + 1):
			var top := GROUND_Y
			if shape == "slope":
				top = GROUND_Y + int(floor(float(dx) * 0.5))
			# DIRT, not stone: stone is hardness 2 and a blast only chips
			# it near the very centre, so a stone platform comes out with
			# no crater at all and the test proves nothing.
			for y in range(top - 26, top):
				store.set_block(Vector3i(at.x + dx, y, at.y + dz), Blocks.DIRT)
			store.set_block(Vector3i(at.x + dx, top, at.y + dz), Blocks.GRASS)
			for y in range(top + 1, top + 26):
				store.set_block(Vector3i(at.x + dx, y, at.y + dz), Blocks.AIR)

## The same sphere _blast() carves. Returns how many blocks it removed.
func _carve(store: ChunkStore, origin: Vector3i, radius: float) -> int:
	var reach := int(ceil(radius))
	var count := 0
	for dy in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if Vector3(dx, dy, dz).length() > radius:
					continue
				var pos := origin + Vector3i(dx, dy, dz)
				var block := store.get_block(pos)
				if block == Blocks.AIR or Blocks.is_liquid(block) \
						or not Blocks.is_breakable(block):
					continue
				var tier := Blocks.hardness(block)
				if tier >= 4:
					continue
				if tier == 3 and pos != origin:
					continue
				if tier == 2 and Vector3(dx, dy, dz).length() > radius * 0.65 \
						and pos != origin:
					continue
				store.set_block(pos, Blocks.AIR)
				count += 1
	return count

## Can a player walk out? Flood from the crater floor across the
## heightmap: stepping UP costs at most one block, dropping is free. If a
## column out past the rim is reachable, there is a way out.
func _check_escape(store: ChunkStore, origin: Vector3i, radius: float,
		shape: String) -> void:
	_checked += 1
	var edge := int(ceil(radius)) + 8
	var start := Vector2i(origin.x, origin.z)
	var seen := {start: true}
	var queue: Array = [start]
	var escaped := false
	while not queue.is_empty() and not escaped:
		var here: Vector2i = queue.pop_front()
		var here_y := store.surface_y(here.x, here.y)
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := Vector2i(here.x + off.x, here.y + off.y)
			if seen.has(next):
				continue
			if absi(next.x - origin.x) > edge or absi(next.y - origin.z) > edge:
				continue
			if store.surface_y(next.x, next.y) - here_y > 1:
				continue          # too tall a step to climb
			seen[next] = true
			queue.append(next)
			if Vector2(next.x - origin.x, next.y - origin.z).length() > radius + 2.0:
				escaped = true
				break
	if not escaped:
		_failures += 1
		print("  %s r=%.1f: TRAPPED — no way out of the crater" % [shape, radius])

## The way out is allowed to cost something, but nothing like the whole
## neighbourhood.
func _check_damage(radius: float, carved: int, ramped: int, shape: String) -> void:
	var budget := int(float(carved) * WASTE_ALLOWED)
	if ramped > budget:
		_failures += 1
		print("  %s r=%.1f: TOO DESTRUCTIVE — sphere %d, way out %d (budget %d)"
			% [shape, radius, carved, ramped, budget])
	else:
		print("  %s r=%.1f: sphere %d blocks, way out %d blocks"
			% [shape, radius, carved, ramped])
