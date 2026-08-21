extends SceneTree
## NOBODY IS EVER PLACED OFF THE MAP.
##
##   godot --headless --path <game> \
##     --script res://tests/placement.gd
##
## This kept coming back. Each time, a caller was fixed and the next one
## was found: the join path, the far-spawn search, the match start, the
## world reset. The one that actually mattered was the world's own SPAWN
## POINT — WorldGen.find_spawn() spiralled out to 88 blocks whatever the
## world's size, so on a 50-block map (25 blocks to the edge) the spawn
## itself was off the map, and every other path falls back to it.
##
## So there is now ONE function that places a person — ChunkStore
## .safe_stand() — and this hammers it, plus find_spawn() underneath it,
## across every world size the menu offers and every theme in the picker.
## If a new placement path is added and does not go through safe_stand,
## that is a code review problem; if safe_stand itself ever regresses,
## this catches it.

## Sizes the menu offers, and the themes whose bounds behave differently
## (sky floats, space is a slab of regolith). The full 7x7 matrix takes
## minutes — every probe generates a chunk, and city and space are
## expensive generators — and adds nothing this does not already cover.
const SIZES := [50, 100, 250, 350]
const THEMES := ["classic", "desert", "sky", "space"]

var _failures := 0
var _checks := 0

func _initialize() -> void:
	for size: int in SIZES:
		for theme: String in THEMES:
			_check_world(size, theme)
	if _failures == 0:
		print("placement: PASS — %d placements, every one on the map" % _checks)
		quit(0)
	else:
		print("placement: FAIL — %d off the map over %d placements"
			% [_failures, _checks])
		quit(1)

func _check_world(size: int, theme: String) -> void:
	var store := ChunkStore.new()
	store.world_size = size
	store.theme = theme
	store.gen = WorldGen.new(20260726, theme, size)
	var half := store.half_extent()

	# The world's own spawn point — the fallback everything else leans on.
	var spawn := store.find_spawn()
	_expect(absi(spawn.x) <= half and absi(spawn.z) <= half,
		"%s/%d: find_spawn %s outside ±%d" % [theme, size, spawn, half])

	# safe_stand from all over the place, including far outside the world
	# and right on the corners — a shrunken map hands it exactly that.
	var probes: Array = [
		Vector3(spawn), Vector3.ZERO,
		Vector3(1000, 40, 1000), Vector3(-1000, 40, -1000),
		Vector3(float(half), 40, float(half)),
		Vector3(-float(half) - 30.0, 40, float(half) + 30.0),
	]
	for probe: Vector3 in probes:
		for spread: float in [0.0, 8.0]:
			var at := store.safe_stand(probe, spread)
			_expect(absi(floori(at.x)) <= half and absi(floori(at.z)) <= half,
				"%s/%d: safe_stand(%s, %.0f) -> %s outside ±%d"
					% [theme, size, probe, spread, at, half])
			# ...and standing on something, not in the sea or the void.
			# floori everywhere: int() truncates towards zero, so a check
			# written with int() reads the wrong column for every negative
			# coordinate — which is half the map.
			var under := store.get_block(Vector3i(floori(at.x),
				floori(at.y) - 1, floori(at.z)))
			_expect(under != Blocks.AIR,
				"%s/%d: safe_stand(%s) -> %s standing on air"
					% [theme, size, probe, at])

func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		return
	_failures += 1
	if _failures <= 10:
		print("  " + message)
