class_name WorldGen
extends RefCounted
## Deterministic procedural island generator (server-side only). Chunks are
## 16x16 columns of CHUNK_H blocks; index = (y * 16 + z) * 16 + x.
##
## The world is a big friendly island ringed by ocean: meadows and forests
## in the middle, beaches at the shore, rolling stone hills with snow caps,
## a few lakes. Scatter (trees, flowers, crit-treats) is hash-based so the
## same seed always builds the same world.

## THE list of built-in maps. Three copies of this had drifted apart,
## which is how "space" ended up in the picker while the server's
## _known_map() silently refused it — clicking Space did nothing at all.
## Anything that needs to know the maps asks here.
const THEMES := ["classic", "desert", "isles", "castles", "city", "sky", "space"]

const CHUNK_SIZE := 16
const CHUNK_H := 80
const SEA_LEVEL := 24
## Playable radius in blocks; beyond it the terrain sinks into open ocean.
const ISLAND_RADIUS := 220.0

var seed_value: int
var theme := "classic"   # classic / desert / isles / castles / city / sky / space
## The world is a SQUARE slab: `world_size` blocks on a side, centred on
## the origin, so a size of 50 means x and z both run -25..+25. Outside it
## nothing is generated at all — the world simply ends, and players are
## stopped at the edge. Bedrock floors the whole slab, so it reads as one
## huge rectangular block you're standing on rather than terrain that
## trails off forever.
var world_size := 250

## True when this column is inside the slab.
func in_bounds(wx: int, wz: int) -> bool:
	var half := world_size / 2
	return wx >= -half and wx <= half and wz >= -half and wz <= half

enum Biome { MEADOW, FOREST, JUNGLE, PINE, FLOWERS, SWAMP }

var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _lakes := FastNoiseLite.new()
var _caves := FastNoiseLite.new()
var _caves2 := FastNoiseLite.new()
var _sky := FastNoiseLite.new()

func _init(p_seed: int, p_theme := "classic", p_size := 250) -> void:
	seed_value = p_seed
	theme = p_theme
	world_size = maxi(p_size, 32)
	_continent.seed = p_seed
	_continent.frequency = 0.004
	_continent.fractal_octaves = 3
	_hills.seed = p_seed + 101
	_hills.frequency = 0.012
	_hills.fractal_octaves = 4
	_detail.seed = p_seed + 202
	_detail.frequency = 0.06
	_detail.fractal_octaves = 2
	# Small biome patches (~40-70 blocks) so a walk crosses several: dense
	# jungle into pine grove into flower field.
	_moisture.seed = p_seed + 303
	_moisture.frequency = 0.018
	_moisture.fractal_octaves = 2
	_temperature.seed = p_seed + 505
	_temperature.frequency = 0.016
	_temperature.fractal_octaves = 2
	_lakes.seed = p_seed + 404
	_lakes.frequency = 0.02
	_lakes.fractal_octaves = 2
	_caves.seed = p_seed + 606
	_caves.frequency = 0.05
	_caves.fractal_octaves = 2
	_caves2.seed = p_seed + 608
	_caves2.frequency = 0.045
	_caves2.fractal_octaves = 2
	_sky.seed = p_seed + 707
	_sky.frequency = 0.011
	_sky.fractal_octaves = 2

## Deterministic per-position hash in [0, 1).
static func hash01(x: int, z: int, salt: int) -> float:
	var h := int(x) * 374761393 + int(z) * 668265263 + salt * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)

## Terrain height at a world column, before carving lakes.
func height_at(wx: int, wz: int) -> int:
	var dist := Vector2(wx, wz).length()
	# Island falloff: 1 in the middle, 0 past the radius.
	var falloff := clampf(1.0 - (dist / ISLAND_RADIUS) * (dist / ISLAND_RADIUS), 0.0, 1.0)
	var base := _continent.get_noise_2d(wx, wz) * 0.5 + 0.5      # 0..1
	var hills := _hills.get_noise_2d(wx, wz) * 0.5 + 0.5
	var detail := _detail.get_noise_2d(wx, wz)
	# Ocean floor ~14, beaches just above sea, hills up to ~+30 over sea.
	if theme == "city":
		return clampi(SEA_LEVEL + 4 + int(detail * 1.2), 2, CHUNK_H - 12)
	if theme == "sky":
		# Skylands: a shallow ocean below, all the action up on the islands.
		return clampi(SEA_LEVEL - 3 + int(detail * 0.8), 2, CHUNK_H - 12)
	if theme == "space":
		# Long rolling swells with real relief — dunes you walk over and
		# see something new behind, not a flat plain with bumps on it.
		var swell := sin(float(wx) * 0.021) * 6.0 + sin(float(wz) * 0.017) * 5.5 \
			+ sin(float(wx + wz) * 0.009) * 7.0
		swell += hills * hills * 26.0 + base * 10.0 + detail * 2.0
		return clampi(int(SEA_LEVEL + 6.0 + swell * 0.75), 2, CHUNK_H - 16)
	if theme == "desert":
		# Flat rolling dunes well above the water table.
		var dune := 14.0 + (base * 18.0 + hills * hills * 30.0) * falloff + detail * 1.8
		return clampi(int(SEA_LEVEL + 4.0 + maxf(dune - SEA_LEVEL, 0.0) * 0.35), 2, CHUNK_H - 12)
	if theme == "isles":
		# Mostly ocean, steep little islands everywhere.
		var bump := maxf(0.0, hills - 0.58) * 110.0
		return clampi(int(16.0 + bump * falloff + detail * 1.2), 2, CHUNK_H - 12)
	var h := 14.0 + (base * 18.0 + hills * hills * 30.0) * falloff + detail * 1.8
	return clampi(int(h), 2, CHUNK_H - 12)

func moisture_at(wx: int, wz: int) -> float:
	return _moisture.get_noise_2d(wx, wz) * 0.5 + 0.5

func biome_at(wx: int, wz: int, h: int) -> int:
	var moist := moisture_at(wx, wz)
	var temp := _temperature.get_noise_2d(wx, wz) * 0.5 + 0.5
	if moist > 0.52 and h <= SEA_LEVEL + 2:
		return Biome.SWAMP
	if moist > 0.6 and temp > 0.55:
		return Biome.JUNGLE
	if moist > 0.55:
		return Biome.FOREST
	if temp < 0.36 and moist < 0.5:
		return Biome.PINE
	if temp > 0.5 and moist > 0.38:
		return Biome.FLOWERS
	return Biome.MEADOW

## Lake carving: dips terrain below sea level inland where the lake noise
## peaks (only where the land is low-ish already, so hills keep their shape).
func lake_depth_at(wx: int, wz: int, h: int) -> int:
	if h > SEA_LEVEL + 8:
		return 0
	var n := _lakes.get_noise_2d(wx, wz)
	if n < 0.45:
		return 0
	return int((n - 0.45) * 26.0)

## Fill a chunk's blocks. Returns a PackedByteArray of CHUNK_SIZE^2 * CHUNK_H.
func generate_chunk(cx: int, cz: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_H)
	for lz in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			var wx := cx * CHUNK_SIZE + lx
			var wz := cz * CHUNK_SIZE + lz
			# Past the edge of the slab there is simply no world. Leaving
			# the column empty is what makes the map a finite rectangle
			# instead of terrain that keeps generating forever.
			if not in_bounds(wx, wz):
				continue
			var h := height_at(wx, wz)
			h -= lake_depth_at(wx, wz, h)
			var moist := moisture_at(wx, wz)
			_fill_column(data, lx, lz, wx, wz, h, moist)
			if theme == "desert":
				for y in range(1, h + 1):
					var b := data[idx(lx, y, lz)]
					if b == Blocks.GRASS or b == Blocks.DIRT:
						data[idx(lx, y, lz)] = Blocks.SAND if y == h else Blocks.SANDSTONE
				if h > SEA_LEVEL + 2 and h + 1 < CHUNK_H and hash01(wx, wz, 61) < 0.015:
					data[idx(lx, h + 1, lz)] = Blocks.DEAD_BUSH
			elif h == SEA_LEVEL + 1 and h + 1 < CHUNK_H and hash01(wx, wz, 62) < 0.1:
				data[idx(lx, h + 1, lz)] = Blocks.CATTAIL
			_carve_caves(data, lx, lz, wx, wz, h)
			# Bedrock floor across the whole slab: you can dig down, but
			# never through the bottom of the world.
			data[idx(lx, 0, lz)] = Blocks.BEDROCK
			# No floating islands over the city (they make no sense above a
			# street grid) and none in space, which has its own ships.
			if theme != "city" and theme != "space":
				_sky_island(data, lx, lz, wx, wz)
			_landmark_column(data, lx, lz, wx, wz, h)
	# The city plants its own street trees, verges and parks; the wild
	# scatter used to sprinkle forest over the pavements on top of it.
	if theme != "city":
		_scatter_features(data, cx, cz)
	return data

## Winding underground caverns, lit by crystals and glowstone. Only under
## dry land (never below sea/lakes, so nothing floods).
func _carve_caves(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int) -> void:
	if h <= SEA_LEVEL + 1:
		return
	# Two noise worms whose intersection is a CONNECTED tunnel network you
	# can actually run through, plus vast cheese caverns lower down with
	# water pools on their floors.
	for y in range(4, h - 3):
		var carve := false
		if absf(_caves.get_noise_3d(wx, y * 1.6, wz)) < 0.085 \
				and absf(_caves2.get_noise_3d(wx, y * 1.6, wz)) < 0.085:
			carve = true
		elif y < 22 and _caves.get_noise_3d(wx * 0.5, y * 1.1, wz * 0.5) > 0.52:
			carve = true
		if carve:
			data[idx(lx, y, lz)] = Blocks.WATER if y <= 8 else Blocks.AIR
	# Walkable funnel entrances from the surface on a wide grid.
	var ax := roundi(float(wx - 48) / 96.0) * 96 + 48
	var az := roundi(float(wz - 48) / 96.0) * 96 + 48
	if hash01(ax, az, 909) < 0.4:
		var dist := Vector2(wx - ax, wz - az).length()
		if dist < 9.0:
			for y in range(maxi(4, h - 9 + int(dist)), h + 1):
				data[idx(lx, y, lz)] = Blocks.AIR
	# Stalagmites, stalactites, crystals, glowstone and mushrooms.
	for y in range(5, h - 3):
		if data[idx(lx, y, lz)] != Blocks.AIR:
			continue
		var roll := hash01(wx, y, wz * 7)
		if data[idx(lx, y - 1, lz)] == Blocks.STONE:
			if roll < 0.02:
				var crystals := [Blocks.CRYSTAL_PINK, Blocks.CRYSTAL_BLUE, Blocks.CRYSTAL_GREEN]
				data[idx(lx, y, lz)] = crystals[int(roll * 150.0) % 3]
			elif roll < 0.03:
				data[idx(lx, y - 1, lz)] = Blocks.GLOWSTONE
			elif roll < 0.05:
				data[idx(lx, y, lz)] = Blocks.MUSHROOM
			elif roll < 0.1:
				data[idx(lx, y, lz)] = Blocks.COBBLE  # stalagmite
		elif y + 1 < CHUNK_H and data[idx(lx, y + 1, lz)] == Blocks.STONE and roll > 0.94:
			data[idx(lx, y, lz)] = Blocks.COBBLE  # stalactite

## Theme landmarks are laid out on a 96-block anchor grid; each column asks
## the pure landmark function what it contributes, so structures far bigger
## than one chunk generate seamlessly: hollow desert pyramids you can
## explore, castle walls in castle-lands, wooden ships among the isles.
func _landmark_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int) -> void:
	# Space packs its landmarks tighter. On the 96-block grid a 250-block
	# world only has room for two or three anchors, and with domes, ships
	# and caverns sharing them you would get exactly one cavern on the
	# whole map — which is what happened.
	var grid := 56.0 if theme == "space" else 96.0
	var ax := floori(wx / grid)
	var az := floori(wz / grid)
	var roll := hash01(ax, az, 900)
	var cx := ax * int(grid) + int(grid) / 2
	var cz := az * int(grid) + int(grid) / 2
	var dx := wx - cx
	var dz := wz - cz
	# Landmarks are bounded by the WORLD, not by a fixed island radius —
	# that constant says nothing about how big this map is.
	if not in_bounds(cx, cz):
		return
	if theme != "space" and Vector2(cx, cz).length() > ISLAND_RADIUS - 30.0:
		return
	if theme == "city":
		_city_column(data, lx, lz, wx, wz, h)
		return
	if theme == "space":
		_space_landmark(data, lx, lz, wx, wz, h, cx, cz, roll, dx, dz)
		return
	if theme == "castles":
		_megacastle_column(data, lx, lz, wx, wz, h)
		return
	if theme == "desert" and roll < 0.65:
		# Pyramids sit ON the dunes: base from the terrain at their center,
		# and never in the water.
		var base := height_at(cx, cz)
		if base <= SEA_LEVEL + 1:
			return
		var size := 14 + int(hash01(ax, az, 901) * 6.0)
		var m := maxi(absi(dx), absi(dz))
		if m > size:
			return
		for k in range(0, size + 1):
			if m > size - k:
				continue
			var y := base + k
			if y >= CHUNK_H:
				break
			var shell: bool = m == size - k or k == 0
			# Entrance tunnel at ground level on the north face.
			if k <= 2 and dz == -(size - k) and absi(dx) <= 1:
				shell = false
			if shell:
				data[idx(lx, y, lz)] = Blocks.SANDSTONE
			else:
				data[idx(lx, y, lz)] = Blocks.AIR
				if k % 5 == 1 and hash01(wx, wz, 902 + k) < 0.02:
					data[idx(lx, y, lz)] = Blocks.GLOWSTONE
	elif false:
		var m := maxi(absi(dx), absi(dz))
		var wall_r := 13
		if m == wall_r or (absi(dx) >= wall_r - 1 and absi(dz) >= wall_r - 1 and m <= wall_r + 1):
			var tower: bool = absi(dx) >= wall_r - 1 and absi(dz) >= wall_r - 1
			var height := 8 if tower else 5
			if not tower and dz == -wall_r and absi(dx) <= 1:
				height = 0  # gate
			for k in range(1, height + 1):
				if h + k < CHUNK_H:
					var crenel: bool = k == height and not tower and posmod(wx + wz, 2) == 1
					if not crenel:
						data[idx(lx, h + k, lz)] = Blocks.COBBLE
			if tower and h + 9 < CHUNK_H:
				data[idx(lx, h + 9, lz)] = Blocks.LANTERN
	elif theme == "isles" and roll < 0.6 and h < SEA_LEVEL - 3:
		# A wooden ship at anchor.
		if absi(dx) > 7 or absi(dz) > 3:
			return
		var hull_w := 3 - maxi(0, absi(dx) - 5)
		if absi(dz) > hull_w:
			return
		var deck := SEA_LEVEL + 1
		for y in range(SEA_LEVEL - 1, deck):
			if absi(dz) == hull_w or absi(dx) == 7:
				data[idx(lx, y, lz)] = Blocks.DARK_PLANKS
			else:
				data[idx(lx, y, lz)] = Blocks.AIR
		data[idx(lx, deck, lz)] = Blocks.PLANKS
		if dx == 0 and dz == 0:
			for k in range(1, 9):
				data[idx(lx, deck + k, lz)] = Blocks.LOG
		elif dz == 0 and absi(dx) <= 3 and dx != 0:
			for k in range(3, 8):
				data[idx(lx, deck + k, lz)] = Blocks.WOOL_WHITE
		elif absi(dx) == 7 and dz == 0:
			data[idx(lx, deck + 1, lz)] = Blocks.LANTERN

## CITY: a real street plan rather than a uniform grid of boxes.
##
## Road centre lines sit every CITY_LOT blocks; every other one (the 64
## grid) is a wide main avenue with a dashed centre line, the rest are
## narrower side streets. Each road carries a pavement, then a grass verge,
## and only then do the lots start — so buildings never grow straight out
## of the tarmac. Lots become parks, squares or buildings whose footprint
## and height are rolled per lot.
const CITY_LOT := 40
const CITY_VERGE := 2         # grass between the pavement and the lot

## Half-width of the tarmac and of the tarmac-plus-pavement for the road
## running down `centre`.
static func _city_tar(centre: int) -> int:
	return 5 if posmod(centre, 80) == 0 else 2

static func _city_kerb(centre: int) -> int:
	return 7 if posmod(centre, 80) == 0 else 4

## Nearest road centre line to a coordinate, on the CITY_LOT grid.
static func _city_centre(v: int) -> int:
	return int(roundf(float(v) / float(CITY_LOT))) * CITY_LOT

func _city_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int) -> void:
	if Vector2(wx, wz).length() > ISLAND_RADIUS - 40.0 or h <= SEA_LEVEL:
		return
	var cx := _city_centre(wx)
	var cz := _city_centre(wz)
	var dx := absi(wx - cx)
	var dz := absi(wz - cz)
	var tar_x := _city_tar(cx)
	var tar_z := _city_tar(cz)
	var kerb_x := _city_kerb(cx)
	var kerb_z := _city_kerb(cz)
	var on_road: bool = dx <= tar_x or dz <= tar_z
	var on_kerb: bool = dx <= kerb_x or dz <= kerb_z

	if on_road:
		data[idx(lx, h, lz)] = Blocks.SLATE
		_city_clear(data, lx, lz, h, 10)
		# Dashed white centre line down the middle of the main avenues,
		# broken at the crossroads so junctions stay clear.
		var main_x: bool = dx == 0 and posmod(cx, 80) == 0 and dz > tar_z
		var main_z: bool = dz == 0 and posmod(cz, 80) == 0 and dx > tar_x
		if (main_x and posmod(wz, 8) < 4) or (main_z and posmod(wx, 8) < 4):
			data[idx(lx, h, lz)] = Blocks.WOOL_WHITE
		return

	if on_kerb:
		data[idx(lx, h, lz)] = Blocks.SANDSTONE
		_city_clear(data, lx, lz, h, 10)
		# Street lights stand on the kerb of the main avenues, spaced out
		# along the road and never in the middle of a junction.
		var post_x: bool = dx == kerb_x and posmod(cx, 80) == 0 and dz > kerb_z \
			and posmod(wz, 16) == 0
		var post_z: bool = dz == kerb_z and posmod(cz, 80) == 0 and dx > kerb_x \
			and posmod(wx, 16) == 0
		if (post_x or post_z) and h + 6 < CHUNK_H:
			for k in range(1, 5):
				data[idx(lx, h + k, lz)] = Blocks.STEEL
			data[idx(lx, h + 5, lz)] = Blocks.LANTERN
		return

	# Grass verge along the front of every lot.
	var verge_x: int = dx - kerb_x
	var verge_z: int = dz - kerb_z
	if verge_x <= CITY_VERGE or verge_z <= CITY_VERGE:
		data[idx(lx, h, lz)] = Blocks.GRASS
		_city_clear(data, lx, lz, h, 10)
		var vroll := hash01(wx, wz, 815)
		if h + 2 < CHUNK_H:
			if vroll < 0.05:
				data[idx(lx, h + 1, lz)] = Blocks.TALL_GRASS
			elif vroll < 0.075:
				data[idx(lx, h + 1, lz)] = [Blocks.FLOWER_RED, Blocks.FLOWER_YELLOW,
					Blocks.FLOWER_PINK, Blocks.DAISY][int(vroll * 400.0) % 4]
			elif vroll < 0.085 and verge_x == CITY_VERGE and verge_z > CITY_VERGE:
				# Street trees, in line, only along the length of a lot.
				data[idx(lx, h + 1, lz)] = Blocks.LOG
				data[idx(lx, h + 2, lz)] = Blocks.LEAVES
		return

	# The LOT index, not the nearest road: rounding here quartered every
	# block into four different buildings that met in the middle.
	var kx := floori(float(wx) / float(CITY_LOT))
	var kz := floori(float(wz) / float(CITY_LOT))
	var lot := hash01(kx, kz, 800)
	if lot < 0.22:
		_city_park(data, lx, lz, wx, wz, h, kx, kz)
		return
	if lot < 0.30:
		_city_car_park(data, lx, lz, wx, wz, h, verge_x, verge_z)
		return
	_city_building(data, lx, lz, wx, wz, h, kx, kz, verge_x, verge_z)

## Air above a surface block, so nothing from the base terrain pass is
## left poking through a road or a lawn.
func _city_clear(data: PackedByteArray, lx: int, lz: int, h: int, up: int) -> void:
	for y in range(h + 1, mini(h + up, CHUNK_H)):
		data[idx(lx, y, lz)] = Blocks.AIR

## Parks: lawn, winding path, scattered trees, flower beds and a pond.
func _city_park(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int,
		kx: int, kz: int) -> void:
	data[idx(lx, h, lz)] = Blocks.GRASS
	_city_clear(data, lx, lz, h, 12)
	# A path crosses the park so it reads as somewhere you walk through.
	var path_wave := int(sin(float(wx) * 0.22 + float(kz)) * 2.5)
	if absi(posmod(wz - kz * CITY_LOT, CITY_LOT) - 16 - path_wave) <= 1:
		data[idx(lx, h, lz)] = Blocks.PATH
		return
	var pond := hash01(kx, kz, 816)
	if pond < 0.45:
		var px := float(wx - kx * CITY_LOT) - 20.0
		var pz := float(wz - kz * CITY_LOT) - 12.0
		if Vector2(px, pz).length() < 4.5:
			data[idx(lx, h, lz)] = Blocks.WATER
			if h + 1 < CHUNK_H and hash01(wx, wz, 817) < 0.25:
				data[idx(lx, h + 1, lz)] = Blocks.LILY_PAD
			return
	var proll := hash01(wx, wz, 806)
	if h + 6 >= CHUNK_H:
		return
	if proll < 0.02:
		# Proper little trees, not two-block shrubs.
		var trunk := 3 + int(hash01(wx, wz, 818) * 3.0)
		for k in range(1, trunk + 1):
			data[idx(lx, h + k, lz)] = Blocks.LOG
		data[idx(lx, h + trunk + 1, lz)] = Blocks.LEAVES
	elif proll < 0.045:
		data[idx(lx, h + 1, lz)] = Blocks.LEAVES  # bush
	elif proll < 0.10:
		data[idx(lx, h + 1, lz)] = Blocks.TALL_GRASS
	elif hash01(floori(float(wx) / 5.0), floori(float(wz) / 5.0), 821) < 0.18 \
			and proll < 0.55:
		# Flower BEDS: a few 5x5 patches, not confetti over the whole lawn.
		data[idx(lx, h + 1, lz)] = [Blocks.FLOWER_RED, Blocks.FLOWER_YELLOW,
			Blocks.FLOWER_PINK, Blocks.BLUEBELL, Blocks.DAISY][
			int(hash01(floori(float(wx) / 5.0), floori(float(wz) / 5.0), 822) * 5.0)]

## Car park: painted bays and chunky parked cars.
func _city_car_park(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int,
		h: int, verge_x: int, verge_z: int) -> void:
	data[idx(lx, h, lz)] = Blocks.PATH
	_city_clear(data, lx, lz, h, 8)
	if posmod(wz, 4) == 0:
		data[idx(lx, h, lz)] = Blocks.SANDSTONE  # bay marking
	if verge_x < CITY_VERGE + 2 or verge_z < CITY_VERGE + 2 or h + 3 >= CHUNK_H:
		return
	var car_x := posmod(wx, 5)
	var car_z := posmod(wz, 4)
	if car_x >= 2 or car_z >= 3:
		return
	if hash01(floori(float(wx) / 5.0), floori(float(wz) / 4.0), 812) > 0.55:
		return
	var paint: int = [Blocks.WOOL_RED, Blocks.WOOL_BLUE, Blocks.WOOL_YELLOW,
		Blocks.WOOL_GREEN, Blocks.WOOL_WHITE][int(hash01(floori(float(wx) / 5.0),
		floori(float(wz) / 4.0), 813) * 5.0)]
	data[idx(lx, h + 1, lz)] = paint
	if car_z == 1:
		data[idx(lx, h + 2, lz)] = Blocks.GLASS

## One building. Footprint (how far it is set back from its verge) and
## height are rolled per lot, so the skyline stops looking stamped out.
##
## Inside, a WIDE staircase climbs one floor at a time. It sits along the
## middle of a wall rather than jammed into a corner, and the floor above
## it is cut away over the whole run — the old two-block lane against the
## corner was nearly impossible to walk up.
func _city_building(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int,
		h: int, kx: int, kz: int, verge_x: int, verge_z: int) -> void:
	# A wide range so the skyline stops looking stamped out: some lots are
	# built almost to the pavement, others sit well back in their garden.
	var setback_x := int(hash01(kx, kz, 804) * 6.0)
	var setback_z := int(hash01(kx, kz, 819) * 6.0)
	if verge_x <= CITY_VERGE + setback_x or verge_z <= CITY_VERGE + setback_z:
		# Front garden: the green asked for at the sides of buildings.
		data[idx(lx, h, lz)] = Blocks.GRASS
		_city_clear(data, lx, lz, h, 12)
		var groll := hash01(wx, wz, 820)
		if h + 2 < CHUNK_H:
			if groll < 0.04:
				data[idx(lx, h + 1, lz)] = Blocks.LEAVES
			elif groll < 0.09:
				data[idx(lx, h + 1, lz)] = Blocks.TALL_GRASS
		return
	var floors := 2 + int(hash01(kx, kz, 801) * 9.0)
	var storey := 5
	# Fit under the world roof, or the top storey gets sliced off and the
	# building ends in a ring of glass with no roof on it.
	var height: int = mini(floors * storey, CHUNK_H - 4 - h)
	if height < storey:
		return
	var material: int = [Blocks.BRICK, Blocks.MARBLE, Blocks.SLATE,
		Blocks.SANDSTONE, Blocks.DARK_PLANKS][int(hash01(kx, kz, 802) * 5.0)]
	var wall: bool = verge_x == CITY_VERGE + setback_x + 1 \
		or verge_z == CITY_VERGE + setback_z + 1
	# The stair run: THREE wide and out in the middle of the floor plate,
	# not a two-block lane wedged into a corner.
	var ux := wx - kx * CITY_LOT
	var uz := wz - kz * CITY_LOT
	var mid := CITY_LOT / 2
	var stair_lane: bool = ux >= mid - 1 and ux <= mid + 1
	var stair_step := uz - (mid - 3)  # climbs a floor, then lands
	var on_stairs: bool = stair_lane and stair_step >= 0 and stair_step < storey
	var stair_void: bool = stair_lane and stair_step >= 0 and stair_step <= storey

	data[idx(lx, h, lz)] = Blocks.PLANKS
	for k in range(1, height + 2):
		var y := h + k
		if y >= CHUNK_H - 2:
			break
		var level := k % storey
		if wall:
			# Window bands with a door at street level, ivy here and there.
			# The very top course is always solid: a parapet, not a ring of
			# glass floating above the roof.
			var window: bool = level != 1 and posmod(wx + wz, 4) != 0 \
				and k < height + 1
			if k <= 3 and verge_z == CITY_VERGE + setback_z + 1 \
					and ux >= mid - 1 and ux <= mid + 1:
				data[idx(lx, y, lz)] = Blocks.AIR  # doorway
			elif not window and hash01(wx, wz + k, 805) < 0.06:
				data[idx(lx, y, lz)] = Blocks.LEAVES
			else:
				data[idx(lx, y, lz)] = Blocks.GLASS if window else material
		elif k == height + 1:
			data[idx(lx, y, lz)] = Blocks.AIR if stair_void else material
		elif on_stairs and level == stair_step:
			data[idx(lx, y, lz)] = Blocks.PLANKS  # one step per block along
		elif level == 0:
			data[idx(lx, y, lz)] = Blocks.AIR if stair_void else Blocks.PLANKS
		elif level == 1 and hash01(wx, wz, 810) < 0.03:
			data[idx(lx, y, lz)] = Blocks.GLOWSTONE
		else:
			data[idx(lx, y, lz)] = Blocks.AIR
	# Rooftop lantern on a corner now and then.
	if wall and hash01(wx, wz, 803) < 0.03 and h + height + 2 < CHUNK_H:
		data[idx(lx, h + height + 2, lz)] = Blocks.LANTERN

## CASTLES: one enormous central castle — curtain walls, corner towers,
## and a tall keep with floors you can fight through.
func _megacastle_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int) -> void:
	var m := maxi(absi(wx), absi(wz))
	if h <= SEA_LEVEL:
		return
	# Curtain wall ring at |max| = 56..58, height 10, gate on the north.
	if m >= 56 and m <= 58:
		var gate: bool = wz <= -56 and absi(wx) <= 3
		if not gate:
			for k in range(1, 11):
				if h + k < CHUNK_H:
					var crenel: bool = k == 10 and posmod(wx + wz, 2) == 1
					if not crenel:
						data[idx(lx, h + k, lz)] = Blocks.COBBLE
		return
	# Corner towers.
	if absi(absi(wx) - 57) <= 4 and absi(absi(wz) - 57) <= 4:
		var tower_r := maxi(absi(absi(wx) - 57), absi(absi(wz) - 57))
		if tower_r <= 4:
			for k in range(1, 16):
				if h + k >= CHUNK_H:
					break
				if tower_r >= 3 or k >= 14:
					data[idx(lx, h + k, lz)] = Blocks.COBBLE
				else:
					data[idx(lx, h + k, lz)] = Blocks.AIR
			if tower_r == 0 and h + 16 < CHUNK_H:
				data[idx(lx, h + 16, lz)] = Blocks.LANTERN
		return
	# The keep: 24x24 at the center — a real great hall, not bumpy terrain.
	# Everything sits on a FLAT court at a fixed height: marble floor, red
	# carpet from the gate to a golden throne, banners, chandeliers, and
	# the staircase up through every floor.
	if m <= 12:
		var base := 28
		if h > base + 20:
			return
		for fy in range(mini(h, base), base):
			data[idx(lx, fy, lz)] = Blocks.STONE  # foundation up to the court
		for k in range(0, 27):
			var y := base + k
			if y >= CHUNK_H - 1:
				break
			var shell: bool = m >= 11
			var floor_slab: bool = k % 6 == 0 and k > 0
			var door: bool = wz <= -11 and absi(wx) <= 2 and k >= 1 and k <= 4
			var window: bool = shell and k % 6 >= 2 and k % 6 <= 3 and posmod(wx + wz, 4) == 0
			var stair_step := -1
			if (wx == 9 or wx == 10) and wz >= 3 and wz <= 7:
				stair_step = wz - 2  # 1..5, then land on the slab
			var stair_hole: bool = (wx == 9 or wx == 10) and wz >= 5 and wz <= 7
			var carpet: bool = absi(wx) <= 1 and wz >= -10 and wz <= 6
			var throne: bool = absi(wx) <= 1 and wz >= 8 and wz <= 9
			if door:
				data[idx(lx, y, lz)] = Blocks.AIR
			elif shell:
				data[idx(lx, y, lz)] = Blocks.GLASS if window else Blocks.STONE
			elif k == 0:
				data[idx(lx, y, lz)] = Blocks.WOOL_RED if carpet else Blocks.MARBLE
			elif throne and (k <= 2 or (k == 3 and wz == 9)):
				data[idx(lx, y, lz)] = Blocks.GOLD
			elif stair_step > 0 and k % 6 == stair_step % 6 and not floor_slab:
				data[idx(lx, y, lz)] = Blocks.PLANKS
			elif floor_slab:
				data[idx(lx, y, lz)] = Blocks.AIR if stair_hole else Blocks.PLANKS
			elif k % 6 == 5 and absi(wx) <= 1 and absi(wz) <= 1:
				data[idx(lx, y, lz)] = Blocks.GLOWSTONE  # chandeliers
			elif m == 10 and k % 6 >= 2 and k % 6 <= 4 and posmod(wx + 3 * wz, 9) == 0:
				data[idx(lx, y, lz)] = Blocks.WOOL_RED  # hall banners
			else:
				data[idx(lx, y, lz)] = Blocks.AIR
		# Clear terrain or trees poking through above the roof.
		for cy in range(base + 27, mini(h + 8, CHUNK_H)):
			data[idx(lx, cy, lz)] = Blocks.AIR
		return

## SPACE: barren grey rolling ground, biosphere domes you can walk into,
## sunken bunkers, and glowing spaceships parked overhead. No water and
## nothing growing — the whole point is that it reads as somewhere else.
func _space_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int,
		h: int) -> void:
	for y in range(0, mini(h + 1, CHUNK_H)):
		var block := Blocks.STONE
		if y == 0:
			block = Blocks.BEDROCK
		elif y == h:
			# Grey moon-ground: pale stone with darker slate showing
			# through in patches. Nothing brown, nothing growing.
			block = Blocks.SLATE if hash01(wx, wz, 71) < 0.25 else Blocks.STONE
		elif y > h - 3:
			block = Blocks.COBBLE if hash01(wx, wz, 72) < 0.4 else Blocks.STONE
		elif y < 6 and hash01(wx, wz + y, 73) < 0.04:
			block = Blocks.MAGMA          # a hot core, glowing in the dark
		data[idx(lx, y, lz)] = block
	# Scattered crystal outcrops so the ground isn't uniformly grey.
	if h + 2 < CHUNK_H and hash01(wx, wz, 74) < 0.0018:
		var crystals := [Blocks.CRYSTAL_PINK, Blocks.CRYSTAL_BLUE,
			Blocks.CRYSTAL_GREEN]
		var gem: int = crystals[int(hash01(wx, wz, 75) * 3.0)]
		data[idx(lx, h + 1, lz)] = gem
		if hash01(wx, wz, 76) < 0.4:
			data[idx(lx, h + 2, lz)] = gem

## The lowest ground anywhere under a circular footprint. Sampled on a
## coarse ring rather than every column — this is called per column while
## generating, so it has to stay cheap, and terrain at this scale does
## not change fast enough for the difference to show.
func _lowest_under(cx: int, cz: int, radius: int) -> int:
	var low := height_at(cx, cz)
	var steps := 12
	for ring in [radius / 2, radius]:
		for i in steps:
			var a := TAU * float(i) / float(steps)
			low = mini(low, height_at(cx + int(cos(a) * float(ring)),
				cz + int(sin(a) * float(ring))))
	return low

## The things you fly to and explore: domes on the surface, bunkers under
## it, and ships hanging in the sky. Laid out on the same 96-block anchor
## grid the other themes' landmarks use, so they generate seamlessly
## across chunk borders.
func _space_landmark(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int,
		h: int, cx: int, cz: int, roll: float, dx: int, dz: int) -> void:
	if roll < 0.42:
		# Biosphere dome: a glass hemisphere on a steel ring, with a way in
		# and a floor of proper grass — the only green on the whole map.
		var radius := 13.0 + roll * 18.0
		var flat := Vector2(dx, dz).length()
		if flat > radius + 1.0:
			return
		# SIT ON THE GROUND. This used to take the height at the dome's
		# centre column and level everything to that, so on any slope the
		# downhill half of the dome — ring, floor and all — hung in the
		# air with a drop underneath it. Take the LOWEST ground anywhere
		# under the footprint instead, and fill up to it: the dome is
		# then buried into the hill on the high side and flush with the
		# ground on the low side, which is what a building does.
		var base := _lowest_under(cx, cz, int(radius) + 1)
		if flat <= radius:
			# Fill any hollow beneath, then level and carpet.
			for y in range(mini(h + 1, CHUNK_H), mini(base, CHUNK_H)):
				data[idx(lx, y, lz)] = Blocks.STONE
			for y in range(base, mini(h + 1, CHUNK_H)):
				data[idx(lx, y, lz)] = Blocks.AIR
			if base < CHUNK_H:
				data[idx(lx, base, lz)] = Blocks.GRASS
			if base + 1 < CHUNK_H and hash01(wx, wz, 77) < 0.06:
				data[idx(lx, base + 1, lz)] = [Blocks.TALL_GRASS,
					Blocks.FLOWER_RED, Blocks.SAPLING][int(hash01(wx, wz, 78) * 3.0)]
		# The shell. Testing one column against the sphere left holes
		# wherever its surface ran steeply — you could walk straight
		# through the dome. Fill every y whose distance from the centre
		# lands inside the shell's thickness, so it is always sealed.
		var centre_y := float(base)
		for y in range(base, mini(CHUNK_H - 1, base + int(radius) + 2)):
			var d := Vector3(float(dx), float(y) - centre_y, float(dz)).length()
			# Generous thickness on purpose: a thinner test leaves gaps
			# wherever the sphere's surface runs steeply through a column,
			# and a dome you can walk through is not a dome.
			if absf(d - radius) > 1.4:
				continue
			# A doorway on the north face, tall enough to walk through.
			if absi(dx) <= 2 and dz < 0 and y < base + 4:
				continue
			data[idx(lx, y, lz)] = Blocks.GLASS
		# A steel ring where it meets the ground.
		if absf(flat - radius) < 1.2 and base < CHUNK_H:
			data[idx(lx, base, lz)] = Blocks.STEEL
			if base + 1 < CHUNK_H and posmod(dx + dz, 7) == 0:
				data[idx(lx, base + 1, lz)] = Blocks.GLOWSTONE
		return
	if roll < 0.72:
		# UNDERGROUND COMMAND CENTRE. Not one big square hall — that read
		# as a warehouse and there was nothing to find in it. This is a
		# warren: small rooms three to four blocks high, four-by-three at
		# the smallest, joined by corridors, spread over THREE levels
		# with stepped shafts between them (one step down every two
		# blocks, so you walk rather than fall).
		#
		# The layout is a pure function of the anchor, like every other
		# landmark here, so it generates the same across chunk borders
		# without anything needing to remember it.
		var half := 30
		if absi(dx) > half or absi(dz) > half:
			return
		var deck_gap := 7             # vertical spacing between levels
		var top_deck := 22            # floor height of the top level
		# Only where there is enough rock ON TOP. Carve this into low
		# ground and the upper rooms come out above the surface as
		# floating steel platforms, which is not an underground base.
		if height_at(cx, cz) < top_deck + 8:
			return
		# Which level does this column belong to? Rooms are laid out on a
		# 10-block grid, and each grid cell picks its own level so the
		# place steps up and down as you walk through it.
		var gx := floori(float(dx + half) / 10.0)
		var gz := floori(float(dz + half) / 10.0)
		var cell_roll := hash01(cx + gx * 37, cz + gz * 91, 610)
		if cell_roll < 0.22:
			return                     # solid rock: not every cell is a room
		var level := int(hash01(cx + gx * 13, cz + gz * 57, 611) * 3.0)
		var floor_y := top_deck - level * deck_gap
		# THE WAY IN: a stepped cut from the surface on the north side,
		# down to the top deck, with a ribbed arch over it so it reads as
		# a built entrance from a long way off. Without this the whole
		# place is sealed and there is no point to any of it.
		if dz < -half + 14 and absi(dx) <= 5:
			var run := float(dz + half) / 14.0        # 0 outside, 1 at the rooms
			var step_y := int(lerpf(float(h) + 1.0, float(top_deck), run))
			# One tread every two blocks, not a slide.
			step_y -= posmod(step_y, 1)
			if absi(dx) <= 3:
				for y in range(mini(step_y, CHUNK_H), mini(step_y + 6, CHUNK_H)):
					data[idx(lx, y, lz)] = Blocks.AIR
				if step_y - 1 > 0:
					data[idx(lx, step_y - 1, lz)] = Blocks.STEEL
				if posmod(dz, 5) == 0:
					var arc := step_y + 5 + (3 - absi(dx))
					if arc < CHUNK_H:
						data[idx(lx, arc, lz)] = Blocks.STEEL
					if absi(dx) == 3 and step_y + 2 < CHUNK_H:
						data[idx(lx, step_y + 2, lz)] = Blocks.GLOWSTONE
			elif posmod(dz, 5) == 0:
				for y in range(mini(step_y, CHUNK_H), mini(step_y + 7, CHUNK_H)):
					data[idx(lx, y, lz)] = Blocks.STEEL
			return
		# Position inside this 10-block cell.
		var ix := posmod(dx + half, 10)
		var iz := posmod(dz + half, 10)
		# The ROOM: 6x5 of the 10, leaving a 4-block wall between cells
		# that the corridors punch through.
		var in_room: bool = ix >= 2 and ix <= 7 and iz >= 2 and iz <= 6
		# CORRIDORS: a 2-wide way out of each room on both axes.
		var in_hall_x: bool = iz >= 4 and iz <= 5
		var in_hall_z: bool = ix >= 4 and ix <= 5
		var head := 3 + int(hash01(cx + gx, cz + gz, 612) * 2.0)   # 3 or 4 high
		if in_room or in_hall_x or in_hall_z:
			for y in range(floor_y, mini(floor_y + head + 1, CHUNK_H)):
				data[idx(lx, y, lz)] = Blocks.AIR
			if floor_y - 1 > 0:
				data[idx(lx, floor_y - 1, lz)] = Blocks.STEEL
			if floor_y + head + 1 < CHUNK_H:
				data[idx(lx, floor_y + head + 1, lz)] = Blocks.STONE
			# Lights down the middle of the corridors and in room corners.
			if in_room and (ix == 2 or ix == 7) and (iz == 2 or iz == 6) \
					and floor_y + head < CHUNK_H:
				data[idx(lx, floor_y + head, lz)] = Blocks.GLOWSTONE
			elif not in_room and posmod(dx + dz, 6) == 0 and floor_y + head < CHUNK_H:
				data[idx(lx, floor_y + head, lz)] = Blocks.GLOWSTONE
			# Consoles: a bank of screens against one wall of some rooms.
			if in_room and iz == 2 and ix >= 3 and ix <= 6 \
					and cell_roll > 0.72 and floor_y + 1 < CHUNK_H:
				data[idx(lx, floor_y, lz)] = Blocks.STEEL
				data[idx(lx, floor_y + 1, lz)] = Blocks.CRYSTAL_BLUE
			return
		# STEPPED SHAFTS between the levels, in the wall between cells:
		# one step down every two blocks, so it is a staircase and not a
		# hole. Only on the cell corners, so they are easy to find again.
		if (ix == 0 or ix == 9) and (iz == 0 or iz == 9):
			var step_floor := top_deck - 2 * deck_gap
			for y in range(step_floor, mini(top_deck + 5, CHUNK_H)):
				data[idx(lx, y, lz)] = Blocks.AIR
			var tread := step_floor + int(float(posmod(dx + dz, 2 * deck_gap * 2)) * 0.5)
			if tread < CHUNK_H:
				data[idx(lx, tread, lz)] = Blocks.STEEL
			return
		return

	# SPACESHIP parked in the sky — the thing this map is supposed to be
	# about. The old one was a 16x6 slab with a glass lid, which read as a
	# floating table. This one has a shape: a tapered hull, a raised
	# cockpit, swept fins and lit engines, in three sizes so a map does
	# not repeat itself.
	var kind := int(hash01(cx, cz, 901) * 3.0)
	var length: int = [13, 19, 26][kind]
	var width: int = [5, 7, 9][kind]
	var ship_y := 46 + int(roll * 20.0)
	if absi(dx) > length + 2 or absi(dz) > width + 3:
		return
	if ship_y + 9 >= CHUNK_H:
		return
	var t := float(dx) / float(length)            # -1 aft .. +1 nose
	# Hull half-width: full amidships, drawn to a point at the nose, cut
	# square at the stern.
	var beam := float(width)
	if t > 0.0:
		beam = float(width) * sqrt(maxf(0.0, 1.0 - t * t * 0.92))
	else:
		beam = float(width) * (0.55 + 0.45 * (1.0 + t))
	var half_beam := int(round(beam))
	var inside: bool = absi(dx) <= length and absi(dz) <= half_beam

	# Swept fins: blades off the stern, angled out and up.
	if not inside:
		if dx < -length / 3 and absi(dz) > half_beam \
				and absi(dz) <= half_beam + int(float(-dx - length / 3) * 0.8) \
				and posmod(dx, 2) == 0:
			var fin_y: int = ship_y + 2 + (absi(dz) - half_beam) / 2
			if fin_y < CHUNK_H:
				data[idx(lx, fin_y, lz)] = Blocks.STEEL
		return

	var deck := ship_y + 1
	var roof := ship_y + 3
	# Belly, deck and hull sides.
	data[idx(lx, ship_y, lz)] = Blocks.STEEL
	for y in range(deck, roof):
		data[idx(lx, y, lz)] = Blocks.STEEL if absi(dz) == half_beam else Blocks.AIR
	data[idx(lx, roof, lz)] = Blocks.STEEL
	# Windows down the flanks.
	if absi(dz) == half_beam and posmod(dx, 3) == 0 and t > -0.7:
		data[idx(lx, deck, lz)] = Blocks.GLASS
	# Cockpit: a glass blister up front, standing proud of the roof.
	if t > 0.35 and absi(dz) <= maxi(half_beam - 1, 1):
		var dome_r := float(maxi(half_beam - 1, 1))
		var cd := Vector2(float(dx) - float(length) * 0.55, float(dz)).length()
		if cd <= dome_r:
			data[idx(lx, roof, lz)] = Blocks.AIR
			if roof + 1 < CHUNK_H:
				data[idx(lx, roof + 1, lz)] = Blocks.GLASS
	# Engines: lit blocks at the stern.
	if dx < -length + 3 and absi(dz) <= half_beam - 1:
		data[idx(lx, deck, lz)] = Blocks.CRYSTAL_BLUE
		if dx < -length + 2:
			data[idx(lx, ship_y, lz)] = Blocks.GLOWSTONE
	# Landing lights along the keel, so it reads from the ground at night.
	if posmod(dx, 5) == 0 and dz == 0 and ship_y - 1 > 0:
		data[idx(lx, ship_y - 1, lz)] = Blocks.GLOWSTONE

## Cheap deterministic "is this cell lit" test for bunker ceilings.
func y_lit(wx: int, wz: int) -> bool:
	return posmod(wx, 5) == 0 and posmod(wz, 5) == 0

## Rare floating islands high above the world — fly up and explore. Grass
## on top, a crystal heart inside the bigger ones.
func _sky_island(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int) -> void:
	if theme == "sky":
		_skylands_column(data, lx, lz, wx, wz)
		return
	var n := _sky.get_noise_2d(wx, wz) * 0.5 + 0.5
	if n < 0.8:
		return
	var body := (n - 0.8) * 40.0   # 0..~4 thickness
	var top := 66
	data[idx(lx, top, lz)] = Blocks.GRASS
	for dy in range(1, int(body) + 1):
		data[idx(lx, top - dy, lz)] = Blocks.DIRT if dy == 1 else Blocks.STONE
	if body > 2.5 and hash01(wx, wz, 44) < 0.1:
		var crystals := [Blocks.CRYSTAL_PINK, Blocks.CRYSTAL_BLUE, Blocks.CRYSTAL_GREEN]
		data[idx(lx, top - 2, lz)] = crystals[int(hash01(wx, wz, 45) * 3.0)]
	var roll := hash01(wx, wz, 46)
	if roll < 0.05:
		data[idx(lx, top + 1, lz)] = Blocks.FLOWER_PINK
	elif roll < 0.09:
		data[idx(lx, top + 1, lz)] = Blocks.TALL_GRASS

## SKYLANDS: floating islands with jittered positions, a mix of small and
## MEGA islands, satellites stacked above the big ones (with waterfalls
## pouring between them), and gentle parabolic plank bridges.
func _sky_params(gx: int, gz: int) -> Dictionary:
	if hash01(gx, gz, 950) >= 0.75 and not (gx == 0 and gz == 0):
		return {}
	var mega := hash01(gx, gz, 955) < 0.15 and not (gx == 0 and gz == 0)
	return {
		"ax": gx * 48 + int((hash01(gx, gz, 956) - 0.5) * 20.0),
		"az": gz * 48 + int((hash01(gx, gz, 957) - 0.5) * 20.0),
		"r": (18.0 + hash01(gx, gz, 951) * 8.0) if mega else (7.0 + hash01(gx, gz, 951) * 7.0),
		"top": 34 + int(hash01(gx, gz, 952) * 22.0),
		"mega": mega,
	}

func _stamp_island(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int,
		ax: int, az: int, r: float, top: int) -> void:
	var dist := Vector2(wx - ax, wz - az).length()
	if dist >= r or top >= CHUNK_H - 2:
		return
	var depth := int((r - dist) * 0.7) + 1
	data[idx(lx, top, lz)] = Blocks.GRASS
	for dy in range(1, depth + 1):
		if top - dy > SEA_LEVEL + 4:
			data[idx(lx, top - dy, lz)] = Blocks.DIRT if dy == 1 else Blocks.STONE
	var roll := hash01(wx, wz, 46)
	if roll < 0.04:
		data[idx(lx, top + 1, lz)] = [Blocks.FLOWER_PINK,
			Blocks.FLOWER_RED, Blocks.BLUEBELL][int(roll * 100.0) % 3]
	elif roll < 0.1:
		data[idx(lx, top + 1, lz)] = Blocks.TALL_GRASS

func _skylands_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int) -> void:
	var gx := roundi(float(wx) / 48.0)
	var gz := roundi(float(wz) / 48.0)
	for dgx in range(gx - 1, gx + 2):
		for dgz in range(gz - 1, gz + 2):
			var p := _sky_params(dgx, dgz)
			if p.is_empty():
				continue
			_stamp_island(data, lx, lz, wx, wz, p.ax, p.az, p.r, p.top)
			# Mega islands carry a small satellite floating above them.
			if p.mega:
				var sat_x: int = p.ax + int((hash01(dgx, dgz, 958) - 0.5) * 16.0)
				var sat_z: int = p.az + int((hash01(dgx, dgz, 959) - 0.5) * 16.0)
				var sat_top: int = p.top + 13
				_stamp_island(data, lx, lz, wx, wz, sat_x, sat_z, 5.5, sat_top)
				# A waterfall pours off the satellite onto the big island.
				if wx == sat_x + 2 and wz == sat_z:
					for y in range(p.top + 1, mini(sat_top, CHUNK_H - 1)):
						if data[idx(lx, y, lz)] == Blocks.AIR:
							data[idx(lx, y, lz)] = Blocks.WATER
			# Waterfall off one rim point of most islands — and it tops out
			# in a small POND sunk into the island, so swimming up the
			# fall lands you somewhere you can actually climb out of.
			if hash01(dgx, dgz, 953) < 0.55:
				var fall_a := hash01(dgx, dgz, 954) * TAU
				var fx: int = p.ax + int(cos(fall_a) * (p.r - 1.5))
				var fz: int = p.az + int(sin(fall_a) * (p.r - 1.5))
				if wx == fx and wz == fz:
					for y in range(SEA_LEVEL - 1, p.top + 1):
						if data[idx(lx, y, lz)] == Blocks.AIR:
							data[idx(lx, y, lz)] = Blocks.WATER
				var pond_d := Vector2(wx - fx, wz - fz).length()
				var isl_d := Vector2(wx - p.ax, wz - p.az).length()
				if pond_d < 2.4 and isl_d < p.r - 0.5 and int(p.top) < CHUNK_H - 1:
					data[idx(lx, p.top, lz)] = Blocks.WATER
					if int(p.top) - 1 > SEA_LEVEL:
						data[idx(lx, p.top - 1, lz)] = Blocks.STONE
			# Bridges to the +x and +z neighbor islands.
			for step_axis in 2:
				var np := _sky_params(dgx + (1 if step_axis == 0 else 0),
					dgz + (0 if step_axis == 0 else 1))
				if np.is_empty():
					continue
				var a_pos := Vector2(p.ax, p.az)
				var b_pos := Vector2(np.ax, np.az)
				var seg := b_pos - a_pos
				if seg.length_squared() < 1.0:
					continue
				var t := clampf((Vector2(wx, wz) - a_pos).dot(seg) / seg.length_squared(), 0.0, 1.0)
				var closest := a_pos + seg * t
				if Vector2(wx, wz).distance_to(closest) < 1.0 and t > 0.02 and t < 0.98:
					# Hold each end flat at its island's top so the bridge
					# actually MEETS the ground on both sides, ramping only
					# through the middle.
					var ramp := smoothstep(0.18, 0.82, t)
					var by := int(lerpf(float(p.top), float(np.top), ramp) - 2.0 * sin(PI * t))
					if by > SEA_LEVEL and by < CHUNK_H - 4 \
							and data[idx(lx, by, lz)] == Blocks.AIR:
						data[idx(lx, by, lz)] = Blocks.PLANKS

static func idx(lx: int, y: int, lz: int) -> int:
	return (y * CHUNK_SIZE + lz) * CHUNK_SIZE + lx

func _fill_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int, moist: float) -> void:
	if theme == "space":
		_space_column(data, lx, lz, wx, wz, h)
		return
	var snow_line := SEA_LEVEL + 22
	var beach_top := SEA_LEVEL + 2
	for y in range(0, mini(h + 1, CHUNK_H)):
		var block := Blocks.STONE
		if y == 0:
			block = Blocks.BEDROCK
		elif y > h - 3 and h <= beach_top:
			block = Blocks.SAND
		elif y == h:
			if h >= snow_line:
				block = Blocks.SNOW
			elif h >= snow_line - 6:
				block = Blocks.STONE
			else:
				block = Blocks.GRASS
		elif y > h - 4:
			block = Blocks.DIRT if h < snow_line - 6 else Blocks.STONE
		data[idx(lx, y, lz)] = block
	# Water fills anything below sea level.
	for y in range(h + 1, SEA_LEVEL + 1):
		if y < CHUNK_H:
			data[idx(lx, y, lz)] = Blocks.WATER

## Surface decoration: trees, flowers, grass tufts, shells, mushrooms,
## pumpkins, berry bushes. All placement is hash-driven per world column.
func _scatter_features(data: PackedByteArray, cx: int, cz: int) -> void:
	for lz in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			var wx := cx * CHUNK_SIZE + lx
			var wz := cz * CHUNK_SIZE + lz
			var ground := _surface_of(data, lx, lz)
			if ground <= 0 or ground + 1 >= CHUNK_H:
				continue
			var surface := data[idx(lx, ground, lz)]
			if surface == Blocks.GRASS:
				_scatter_grass_column(data, lx, lz, wx, wz, ground)
			elif surface == Blocks.SAND and ground <= SEA_LEVEL + 2:
				if hash01(wx, wz, 15) < 0.008:
					data[idx(lx, ground + 1, lz)] = Blocks.SHELL

## Per-biome surface decoration. Trees only fully inside the chunk so
## canopies never cross borders (generation stays independent per chunk).
func _scatter_grass_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, ground: int) -> void:
	var biome := biome_at(wx, wz, ground)
	var interior := lx >= 3 and lx < 13 and lz >= 3 and lz < 13
	var tree_roll := hash01(wx, wz, 7)
	match biome:
		Biome.SWAMP:
			if hash01(wx, wz, 20) < 0.14:
				data[idx(lx, ground, lz)] = Blocks.WATER
				return
			if hash01(wx, wz, 12) < 0.03:
				data[idx(lx, ground + 1, lz)] = Blocks.MUSHROOM
			elif hash01(wx, wz, 9) < 0.16:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif interior and tree_roll < 0.012:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 0)
		Biome.JUNGLE:
			if lx >= 4 and lx < 12 and lz >= 4 and lz < 12 and tree_roll < 0.09:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 1)
			elif hash01(wx, wz, 9) < 0.22:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 12) < 0.012:
				data[idx(lx, ground + 1, lz)] = Blocks.MUSHROOM
			elif hash01(wx, wz, 10) < 0.02:
				data[idx(lx, ground + 1, lz)] = Blocks.FLOWER_PINK
			elif hash01(wx, wz, 14) < 0.03:
				data[idx(lx, ground + 1, lz)] = Blocks.DAISY
			elif hash01(wx, wz, 15) < 0.02:
				data[idx(lx, ground + 1, lz)] = Blocks.BLUEBELL
		Biome.FOREST:
			if interior and tree_roll < 0.03:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 0)
			elif hash01(wx, wz, 9) < 0.1:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 12) < 0.007:
				data[idx(lx, ground + 1, lz)] = Blocks.MUSHROOM
			elif hash01(wx, wz, 14) < 0.08:
				data[idx(lx, ground + 1, lz)] = Blocks.FERN
		Biome.PINE:
			if lx >= 2 and lx < 14 and lz >= 2 and lz < 14 and tree_roll < 0.05:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 2)
			elif hash01(wx, wz, 9) < 0.03:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 14) < 0.05:
				data[idx(lx, ground + 1, lz)] = Blocks.FERN
		Biome.FLOWERS:
			if hash01(wx, wz, 10) < 0.15:
				var pick := hash01(wx, wz, 11)
				var flower := Blocks.FLOWER_RED
				if pick > 0.66:
					flower = Blocks.FLOWER_PINK
				elif pick > 0.33:
					flower = Blocks.FLOWER_YELLOW
				data[idx(lx, ground + 1, lz)] = flower
			elif hash01(wx, wz, 9) < 0.08:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 13) < 0.01:
				data[idx(lx, ground + 1, lz)] = Blocks.BERRY_BUSH
			elif hash01(wx, wz, 16) < 0.06:
				data[idx(lx, ground + 1, lz)] = Blocks.WHEAT_PLANT
			elif hash01(wx, wz, 17) < 0.03:
				data[idx(lx, ground + 1, lz)] = Blocks.BLUEBELL
			elif interior and tree_roll < 0.004:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 0)
		_:
			# Shooter cover: rare ruined wall stubs and stone crags.
			if interior and hash01(wx, wz, 50) < 0.0012:
				var h := 2 + int(hash01(wx, wz, 51) * 3.0)
				for dy in h:
					if hash01(wx, dy, wz) < 0.8:
						data[idx(lx, ground + 1 + dy, lz)] = Blocks.COBBLE
				if lx < 13:
					data[idx(lx + 1, ground + 1, lz)] = Blocks.COBBLE
				return
			if interior and hash01(wx, wz, 52) < 0.0012:
				for dy in 3 + int(hash01(wx, wz, 53) * 4.0):
					data[idx(lx, ground + 1 + dy, lz)] = Blocks.STONE
				return
			if interior and tree_roll < 0.006:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 0)
			elif hash01(wx, wz, 9) < 0.05:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 10) < 0.02:
				var pick := hash01(wx, wz, 11)
				data[idx(lx, ground + 1, lz)] = Blocks.FLOWER_YELLOW if pick > 0.5 else Blocks.FLOWER_RED
			elif hash01(wx, wz, 13) < 0.004:
				data[idx(lx, ground + 1, lz)] = Blocks.BERRY_BUSH
			elif hash01(wx, wz, 14) < 0.0016:
				data[idx(lx, ground + 1, lz)] = Blocks.PUMPKIN

## Highest non-air, non-water block of a local column (during generation).
func _surface_of(data: PackedByteArray, lx: int, lz: int) -> int:
	for y in range(CHUNK_H - 1, -1, -1):
		var b := data[idx(lx, y, lz)]
		if b != Blocks.AIR and b != Blocks.WATER:
			return y
	return -1

## kind: 0 = oak blob, 1 = tall wide jungle canopy, 2 = narrow pine.
func _plant_tree(data: PackedByteArray, lx: int, base_y: int, lz: int, size_roll: float, kind := 0) -> void:
	var trunk := 3 + int(size_roll * 3.0)
	var radius := 2.45
	var squash := 1.4
	if kind == 1:
		trunk = 7 + int(size_roll * 4.0)
		radius = 3.4
		squash = 2.0
	elif kind == 2:
		trunk = 5 + int(size_roll * 3.0)
		radius = 1.4
		squash = 0.8
	if base_y + trunk + 3 >= CHUNK_H:
		return
	for i in trunk:
		data[idx(lx, base_y + i, lz)] = Blocks.LOG
	var top := base_y + trunk
	var reach := int(ceil(radius))
	for dy in range(-2, 3):
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var r := Vector3(dx, dy * squash, dz).length()
				if r > radius:
					continue
				var px := lx + dx
				var pz := lz + dz
				var py := top + dy
				if px < 0 or px >= CHUNK_SIZE or pz < 0 or pz >= CHUNK_SIZE:
					continue
				if py <= 0 or py >= CHUNK_H:
					continue
				if data[idx(px, py, pz)] == Blocks.AIR:
					data[idx(px, py, pz)] = Blocks.LEAVES

## A decent spawn: walk outward from the middle until we find grass above sea
## level. Returns the block position of the ground (players stand on top).
func find_spawn() -> Vector3i:
	if theme == "sky":
		# The (0,0) island always exists; land on top of it.
		return Vector3i(0, 36 + int(hash01(0, 0, 952) * 22.0), 0)
	# The search NEVER leaves the slab. It used to spiral out to 88 blocks
	# whatever the world's size, so on a 50-block map (25 blocks from the
	# origin to the edge) the spawn point itself was off the map — and
	# every other placement falls back to it, which is why players kept
	# turning up in the void however many times the callers were fixed.
	var limit := maxf(4.0, float(world_size) / 2.0 - 6.0)
	for radius in range(0, 12):
		var ring := minf(float(radius) * 8.0, limit)
		for attempt in 24:
			var angle := hash01(radius, attempt, 55) * TAU
			var wx := int(cos(angle) * ring)
			var wz := int(sin(angle) * ring)
			if not in_bounds(wx, wz):
				continue
			var h := height_at(wx, wz)
			h -= lake_depth_at(wx, wz, h)
			if h > SEA_LEVEL + 1 and h < SEA_LEVEL + 14:
				return Vector3i(wx, h, wz)
	return Vector3i(0, height_at(0, 0), 0)
