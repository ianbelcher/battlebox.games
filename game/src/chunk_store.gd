class_name ChunkStore
extends RefCounted
## Server-side authoritative world storage. Chunks come from one of two
## sources — the procedural generator or a read-only Minecraft world — and
## the source world is never modified.
##
## THIS WRITES NOTHING TO DISK. The world lives in memory and dies with
## the process, on purpose.
##
## It used to zstd every edited chunk out to a file every 25 seconds — and
## then delete every one of those files on the next boot, because the world
## has always been regenerated fresh on restart. Compressing and writing a
## few hundred chunks on a timer is real work on the server's only thread,
## and nothing ever read a byte of it. The seed, theme and size were kept
## in a world.cfg beside them, which meant a "clean table" restart quietly
## came back with the last session's map, its size and its time of day.
##
## What a fresh server is now is decided entirely by its environment
## (WORLD_SEED / WORLD_THEME / WORLD_SIZE / WORLD_SOURCE) and by whoever
## changes the map from the menu afterwards. There is no third source of
## truth sitting in a file, and no volume to lose.
##
## The one thing that has to be true for this to be safe: an edited chunk
## may NEVER be dropped from the cache. It has no file to come back from,
## so evicting one would silently regenerate the terrain underneath
## somebody's fort. `trim_cache()` only ever drops chunks that are still
## exactly as generated.

const RAW_CHUNK_BYTES := WorldGen.CHUNK_SIZE * WorldGen.CHUNK_SIZE * WorldGen.CHUNK_H
## Chunks farther than this (in chunks) from the origin are ocean border.
const WORLD_RADIUS_CHUNKS := 24
## The world every fresh server makes, unless WORLD_SEED says otherwise.
## Fixed rather than random so a restart is a place people recognise —
## the same island, freshly built, not somewhere new every time.
const DEFAULT_SEED := 20260726

var source := "procedural"  # or "mca"
var theme := "classic"
## Side of the square world, in blocks — a size of 50 is a 50x50 slab
## centred on the origin. Changing it regenerates the world, because the
## terrain itself is cut to this shape.
var world_size := 250
var gen: WorldGen
var mca: McaWorld = null

var _cache: Dictionary = {}       # Vector2i -> PackedByteArray
## Chunks somebody has changed. These are the world — there is no copy of
## them anywhere else — so they are pinned in the cache for the lifetime of
## the world and only `reset_world()` lets them go.
var _edited: Dictionary = {}      # Vector2i -> true

func _init() -> void:
	source = EnvConfig.text("WORLD_SOURCE", "procedural")
	theme = EnvConfig.text("WORLD_THEME", "classic")
	world_size = EnvConfig.number("WORLD_SIZE", world_size)
	var seed_value := EnvConfig.number("WORLD_SEED", DEFAULT_SEED)
	gen = WorldGen.new(seed_value, theme, world_size)
	if source == "mca":
		var mca_dir := OS.get_environment("WORLD_MCA_DIR")
		mca = McaWorld.new(mca_dir)
		if not mca.is_valid():
			push_error("WORLD_SOURCE=mca but no region files at '%s'; falling back to procedural" % mca_dir)
			source = "procedural"
			mca = null
	print("World store: source=%s seed=%d theme=%s size=%d (memory only, nothing on disk)" % [
		source, seed_value, theme, world_size])

func in_bounds(cpos: Vector2i) -> bool:
	return absi(cpos.x) <= WORLD_RADIUS_CHUNKS and absi(cpos.y) <= WORLD_RADIUS_CHUNKS

## Half the slab, in blocks. The world is a square `world_size` on a side
## centred on the origin, so anything placed outside ±this is off the map.
func half_extent() -> int:
	return world_size / 2

## THE bounds check for anything the server puts in the world — crates,
## kits, animals, structures, players at the drop. Everything used to
## work off its own radius (the storm's, the arena's, a hard-coded
## number), and on a small world those all reached past the edge of the
## slab and dropped things into the void.
##
## `margin` keeps a thing clear of the very edge, so a crate is never
## half-buried in the border wall.
func inside_world(wx: int, wz: int, margin := 2) -> bool:
	var limit := half_extent() - margin
	return absi(wx) <= limit and absi(wz) <= limit

## THE ONE FUNCTION THAT PLACES A PLAYER.
##
## Every path that puts a person somewhere — joining, respawning, a match
## starting, a world reset — goes through here, and what comes out is
## always inside the slab and always standing on the ground.
##
## It exists because the alternative was tried and failed repeatedly:
## each caller doing its own bounds check meant each new caller was a new
## chance to forget, and the one that mattered most (the world's spawn
## point itself) was wrong, so fixing the callers fixed nothing.
##
## `spread` scatters around the requested spot; the result is pulled back
## inside the world first and grounded second, in that order, because
## grounding an out-of-bounds column tells you nothing.
func safe_stand(around: Vector3, spread := 0.0) -> Vector3:
	var wx := around.x
	var wz := around.z
	if spread > 0.0:
		wx += randf_range(-spread, spread)
		wz += randf_range(-spread, spread)
	var here := clamp_inside(Vector3(wx, 0.0, wz), 4)
	# floori, NOT int(): int() truncates towards zero, so int(-45.5) is
	# -45 — a different column from the one -45.5 actually sits in. Every
	# world coordinate west or north of the origin is off by one if you
	# get this wrong, which is most of the map.
	var gx := floori(here.x)
	var gz := floori(here.z)
	# Try where we were asked, then step in towards the middle: better a
	# few blocks inland than standing in the sea or over a hole.
	for tries in 10:
		var found := _stand_at(gx, gz)
		if found.y > 0.0:
			return found
		var inward := Vector2(-float(gx), -float(gz))
		if inward.length() < 1.0:
			break
		inward = inward.normalized() * 6.0
		var edge := float(half_extent() - 4)
		gx = floori(clampf(float(gx) + inward.x, -edge, edge))
		gz = floori(clampf(float(gz) + inward.y, -edge, edge))
	# Still nothing: sweep the world properly rather than guessing. This
	# is the branch that used to lift people to SEA_LEVEL, which on a map
	# whose ground sits BELOW sea level (space has no sea at all) left
	# them standing in mid-air.
	var edge2 := half_extent() - 4
	for ring in range(0, edge2, 5):
		for step in 16:
			var a := TAU * float(step) / 16.0
			var probe := _stand_at(floori(cos(a) * float(ring)),
				floori(sin(a) * float(ring)))
			if probe.y > 0.0:
				return probe
	# The world is a hole. Stand on the origin column, whatever it is.
	return Vector3(0.5, float(maxi(surface_y(0, 0), 1)) + 1.2, 0.5)

## A standable spot in this column, or y <= 0 if there is not one: solid
## ground under foot, nothing liquid, and clear of the sky and the void.
func _stand_at(gx: int, gz: int) -> Vector3:
	if not inside_world(gx, gz, 2):
		return Vector3.ZERO
	var y := surface_y(gx, gz)
	if y <= 1 or y >= WorldGen.CHUNK_H - 4:
		return Vector3.ZERO
	var under := get_block(Vector3i(gx, y, gz))
	if under == Blocks.AIR or Blocks.is_liquid(under):
		return Vector3.ZERO
	return Vector3(float(gx) + 0.5, float(y) + 1.2, float(gz) + 0.5)

## The same point, pulled back inside the slab instead of rejected. Use
## this where a thing MUST exist somewhere (a player's drop) rather than
## where it can simply be skipped (one crate out of forty).
func clamp_inside(pos: Vector3, margin := 3) -> Vector3:
	var limit := float(half_extent() - margin)
	return Vector3(clampf(pos.x, -limit, limit), pos.y,
		clampf(pos.z, -limit, limit))

## Cut ONE way out of a crater — a narrow ramp, nothing more.
##
## The job is to stop a blast trapping somebody, and that is all. An
## earlier version of this relaxed the whole heightmap around the crater
## until no column stood more than a block above its neighbour, which
## does guarantee escape — by flattening a bowl two radii wide. A big
## shooter round ate hundreds of blocks and left a smooth circular arena.
## That is far more destructive than the explosion it was meant to be
## cleaning up after, and it is not what a crater should look like.
##
## So instead: find the crater floor, pick the direction where the
## surrounding ground sits LOWEST, and cut a three-wide furrow out that
## way, rising one block per step until it meets ground level. Escape is
## guaranteed by construction — every step of the ramp is exactly one
## block above the last — and the cost is a few dozen blocks in one
## direction rather than everything in a circle.
##
## GROUND THAT MAY NOT BE CUT, as [centre_x, centre_z, radius] triples in
## world coordinates. WorldNode fills this with the capture-the-flag mounds
## when a round starts and empties it when one ends.
##
## The ramp is the one carve that does not go through `WorldNode._can_carve`
## — it happens down here, where there is no notion of a flag — so without
## this a blast beside a mound would still cut a furrow through it and the
## "indestructible" flag would end up with a trench in it.
var no_carve: Array = []

func _carve_blocked(wx: int, wz: int) -> bool:
	for zone: Array in no_carve:
		if Vector2(float(wx) - float(zone[0]), float(wz) - float(zone[1])).length() \
				<= float(zone[2]):
			return true
	return false

## Returns what it cleared, for broadcasting.
func carve_exit_ramp(origin: Vector3i, radius: float) -> Array:
	var cleared: Array = []
	# The crater floor: fall down the origin column through the hole the
	# blast just made.
	var floor_y := origin.y
	while floor_y > 2 and get_block(Vector3i(origin.x, floor_y - 1, origin.z)) == Blocks.AIR:
		floor_y -= 1
	var reach := int(ceil(radius)) + 2
	# Out towards the lowest ground: the shortest ramp, and the one that
	# looks most like the blast simply threw the dirt that way.
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var best_dir: Vector2i = dirs[0]
	var best_h := 1 << 30
	for d: Vector2i in dirs:
		var h := surface_y(origin.x + d.x * reach, origin.z + d.y * reach)
		if h < best_h:
			best_h = h
			best_dir = d
	var perp := Vector2i(-best_dir.y, best_dir.x)
	# Walk outwards keeping a promise: each column along the way is at
	# most ONE block higher than the one before it. Following the real
	# height of the previous column is the whole trick — an earlier
	# version compared against an idealised "floor + step" line instead,
	# which rises even while the crater floor is flat, so by the time it
	# reached the rim the budget was already generous enough to accept a
	# two-block wall and it cut nothing at all.
	var prev := surface_y(origin.x, origin.z)
	for step in range(1, reach + int(ceil(radius)) + 6):
		var cx := origin.x + best_dir.x * step
		var cz := origin.z + best_dir.y * step
		var ground := surface_y(cx, cz)
		var want := prev + 1
		if ground > want:
			for w: int in [-1, 0, 1]:
				var px: int = cx + perp.x * w
				var pz: int = cz + perp.y * w
				var col_top := surface_y(px, pz)
				for y in range(want + 1, col_top + 1):
					var pos := Vector3i(px, y, pz)
					var block := get_block(pos)
					if block == Blocks.AIR:
						continue
					if _carve_blocked(px, pz):
						break
					# Steel and diamond stop the ramp dead, same as they
					# stop the blast. Better a short ramp than a hole
					# through a vault door.
					if not Blocks.is_breakable(block) or Blocks.hardness(block) >= 3:
						break
					set_block(pos, Blocks.AIR)
					cleared.append(pos)
			ground = mini(ground, want)
		prev = ground
		# Past the rim and standing on ground that needed no help: the
		# way out is complete.
		if float(step) > radius and ground <= want:
			break
	return cleared

func get_chunk(cpos: Vector2i) -> PackedByteArray:
	if _cache.has(cpos):
		return _cache[cpos]
	# A miss can only ever be a chunk nobody has touched: edited ones are
	# pinned in the cache and never evicted, so reaching here means the
	# generator (or the .mca) is the whole truth about this chunk.
	var data: PackedByteArray
	if not in_bounds(cpos):
		data = _border_chunk()
	elif mca != null:
		data = mca.read_chunk(cpos.x, cpos.y)
		if data.is_empty():
			data = _border_chunk()
	else:
		data = gen.generate_chunk(cpos.x, cpos.y)
	_cache[cpos] = data
	return data

## Compressed payload for the wire.
func get_chunk_compressed(cpos: Vector2i) -> PackedByteArray:
	return get_chunk(cpos).compress(FileAccess.COMPRESSION_ZSTD)

func get_block(pos: Vector3i) -> int:
	if pos.y < 0 or pos.y >= WorldGen.CHUNK_H:
		return Blocks.AIR
	var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	var data := get_chunk(cpos)
	var lx := posmod(pos.x, 16)
	var lz := posmod(pos.z, 16)
	return data[WorldGen.idx(lx, pos.y, lz)]

func set_block(pos: Vector3i, block: int) -> void:
	if pos.y <= 0 or pos.y >= WorldGen.CHUNK_H:
		return
	var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	if not in_bounds(cpos):
		return
	var data := get_chunk(cpos)
	var lx := posmod(pos.x, 16)
	var lz := posmod(pos.z, 16)
	data[WorldGen.idx(lx, pos.y, lz)] = block
	_cache[cpos] = data
	# From here on this chunk IS the world — regenerating it would undo
	# whatever was just built — so it is pinned against eviction.
	_edited[cpos] = true

## Top solid/water surface for spawning things on.
func surface_y(wx: int, wz: int) -> int:
	var cpos := Vector2i(floori(wx / 16.0), floori(wz / 16.0))
	var data := get_chunk(cpos)
	var lx := posmod(wx, 16)
	var lz := posmod(wz, 16)
	for y in range(WorldGen.CHUNK_H - 1, -1, -1):
		var b := data[WorldGen.idx(lx, y, lz)]
		if b != Blocks.AIR and not Blocks.is_cross(b):
			return y
	return 0

func find_spawn() -> Vector3i:
	if mca != null:
		return mca.find_spawn()
	return gen.find_spawn()

## Where imported Minecraft maps live (env override, docker, or repo dir).
static func maps_root() -> String:
	var override := OS.get_environment("WORLD_MCA_DIR")
	if not override.is_empty():
		return override
	for candidate in ["/opt/battlebox/maps",
			ProjectSettings.globalize_path("res://").path_join("../maps")]:
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
	return "maps"

## The map library: loose region files at the top level are one map;
## each subfolder
## with .mca files inside = its own selectable map (name from map.cfg).
static func list_maps() -> Array:
	var out: Array = []
	var root := maps_root()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".mca"):
			out.append({"key": "mca", "name": "Imported World"})
			break
	for sub in dir.get_directories():
		var sub_dir := DirAccess.open(root.path_join(sub))
		if sub_dir == null:
			continue
		var has_region := false
		for file in sub_dir.get_files():
			if file.ends_with(".mca"):
				has_region = true
				break
		if not has_region and DirAccess.dir_exists_absolute(root.path_join(sub).path_join("region")):
			has_region = true
		if has_region:
			var map_cfg := ConfigFile.new()
			map_cfg.load(root.path_join(sub).path_join("map.cfg"))
			out.append({"key": "mca:" + sub,
				"name": str(map_cfg.get_value("map", "name", sub.capitalize()))})
	return out

## Wipe every edit and regenerate from a brand-new seed (map reset vote).
func reset_world(new_seed: int, map_name := "", new_size := 0) -> void:
	if new_size > 0:
		world_size = new_size
	# Dropping both is the entire reset: the world only ever existed here.
	_cache.clear()
	_edited.clear()
	_apply_map(map_name, new_seed)

## Wipe edits and switch to a chosen theme, or "mca" for an imported
## Minecraft map (whatever is in maps/).
func set_map(map_name: String, new_seed: int) -> void:
	reset_world(new_seed, map_name)

var current_map_key := ""

func _apply_map(map_name: String, new_seed: int) -> void:
	if map_name.is_empty():
		map_name = WorldGen.THEMES[randi() % WorldGen.THEMES.size()]
	current_map_key = map_name
	if map_name == "mca" or map_name.begins_with("mca:"):
		source = "mca"
		var mca_dir := maps_root()
		if map_name.begins_with("mca:"):
			mca_dir = mca_dir.path_join(map_name.trim_prefix("mca:"))
		mca = McaWorld.new(mca_dir)
		if mca.is_valid():
			# Per-map settings, else the top-level defaults.
			var map_cfg := ConfigFile.new()
			map_cfg.load(mca_dir.path_join("map.cfg"))
			mca.center = Vector2i(
				int(map_cfg.get_value("map", "center_x", 256)),
				int(map_cfg.get_value("map", "center_z", 256)))
			mca.y0 = int(map_cfg.get_value("map", "y0", mca.y0))
		else:
			push_error("No importable map found at '%s'" % mca_dir)
			source = "procedural"
			mca = null
	else:
		source = "procedural"
		mca = null
		theme = map_name
	gen = WorldGen.new(new_seed, theme, world_size)

## Keep memory bounded on a long-running server by dropping chunks that can
## be regenerated exactly — nothing else.
##
## An EDITED chunk is never dropped. It has no file to come back from, so
## evicting one would quietly hand back generated terrain in its place and
## a fort would stop existing. That is the whole cost of not writing to
## disk, and it is paid here.
##
## The ceiling that puts on memory is the world, not the uptime: the slab
## is at most 49x49 chunks of 20 KiB, so even a world edited corner to
## corner is under 50 MiB.
## How many chunks are in memory, and how many of those are somebody's
## build. Edited chunks have no file to come back from, so the second
## number is the part of the world that only exists here.
func cached_count() -> int:
	return _cache.size()

func edited_count() -> int:
	return _edited.size()

func trim_cache() -> int:
	if _cache.size() <= 1400:
		return 0
	var dropped := 0
	for cpos: Vector2i in _cache.keys():
		if _cache.size() <= 1000:
			break
		if _edited.has(cpos):
			continue
		_cache.erase(cpos)
		dropped += 1
	return dropped

## Open ocean for everything outside the playable radius / missing MCA chunks.
func _border_chunk() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(RAW_CHUNK_BYTES)
	for lz in 16:
		for lx in 16:
			data[WorldGen.idx(lx, 0, lz)] = Blocks.BEDROCK
			for y in range(1, 12):
				data[WorldGen.idx(lx, y, lz)] = Blocks.STONE
			for y in range(12, WorldGen.SEA_LEVEL + 1):
				data[WorldGen.idx(lx, y, lz)] = Blocks.WATER
	return data
