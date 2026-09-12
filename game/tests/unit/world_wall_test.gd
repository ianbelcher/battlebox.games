extends TestCase
## The wall around the world, and where the caverns world starts you.

func test_the_edge_of_the_world_is_a_wall_ten_above_sea_level() -> void:
	var gen := WorldGen.new(7, "classic", 64)
	# x = 32 is the last column inside a 64-wide slab: chunk 2, lx 0.
	var data := gen.generate_chunk(2, 0)
	# Ten above sea level, or the local ground plus a clearing margin,
	# whichever is taller — a wall that towers to the top of the world
	# regardless of what is next to it reads as a cliff, not a boundary.
	var wall_top := maxi(WorldGen.SEA_LEVEL + 10, gen.height_at(32, 0) + 14)
	for y in [0, 20, wall_top]:
		equal(int(data[WorldGen.idx(0, y, 0)]), Blocks.BEDROCK,
			"the border column is bedrock at y=%d" % y)
	equal(int(data[WorldGen.idx(0, wall_top + 1, 0)]), Blocks.AIR,
		"but open sky above the wall's top")
	equal(int(data[WorldGen.idx(1, WorldGen.CHUNK_H - 1, 0)]), Blocks.AIR,
		"the column inside it is not")
	check(gen.on_border(32, 5) and gen.on_border(-4, -32) and not gen.on_border(31, 31),
		"on_border is the outermost ring")

func test_the_caverns_start_you_underground() -> void:
	var gen := WorldGen.new(3, "caverns", 200)
	var spawn := gen.find_spawn()
	check(spawn.y < WorldGen.CAVERN_TOP - WorldGen.CAVERN_CRUST,
		"the spawn is under the crust, not on the plain: %s" % spawn)
	var cpos := Vector2i(floori(spawn.x / 16.0), floori(spawn.z / 16.0))
	var data := gen.generate_chunk(cpos.x, cpos.y)
	var lx := posmod(spawn.x, 16)
	var lz := posmod(spawn.z, 16)
	check(data[WorldGen.idx(lx, spawn.y, lz)] != Blocks.AIR, "standing on ground")
	equal(int(data[WorldGen.idx(lx, spawn.y + 1, lz)]), Blocks.AIR, "with air over it")

func test_the_caverns_have_no_magma_and_have_water() -> void:
	var gen := WorldGen.new(3, "caverns", 200)
	var water := 0
	var magma := 0
	for cx in range(-3, 3):
		for cz in range(-3, 3):
			var data := gen.generate_chunk(cx, cz)
			water += data.count(Blocks.WATER)
			magma += data.count(Blocks.MAGMA)
	equal(magma, 0, "no magma anywhere")
	check(water > 200, "lakes under the plain (%d water blocks)" % water)

func test_a_caverns_stand_is_in_a_hall_with_headroom() -> void:
	# ChunkStore reads its world from the environment; this is the world
	# a caverns room is spawned with. Every place it offers to stand has
	# to be under the crust with room for a body, or the body is lifted
	# out through the rock onto the plain.
	var store := ChunkStore.new()
	store.theme = "caverns"
	store.world_size = 100
	store.gen = WorldGen.new(20260726, "caverns", 100)
	var checked := 0
	for wx in range(-40, 41, 8):
		for wz in range(-40, 41, 8):
			var y := store.stand_y(wx, wz)
			if y < 0:
				continue
			checked += 1
			check(y < WorldGen.CAVERN_TOP - WorldGen.CAVERN_CRUST,
				"(%d,%d) stands under the crust: y=%d" % [wx, wz, y])
			for up in [1, 2, 3]:
				# Open, not necessarily empty: a mushroom on the floor is
				# something a body walks through.
				check(not Blocks.is_solid(store.get_block(Vector3i(wx, y + up, wz))),
					"(%d,%d) has room %d over its floor" % [wx, wz, up])
	check(checked > 20, "enough columns offered somewhere to stand (%d)" % checked)
	var spot := store.safe_stand(Vector3(store.find_spawn()), 3.0)
	check(spot.y < WorldGen.CAVERN_TOP - WorldGen.CAVERN_CRUST,
		"the spawn stands in the halls: %s" % spot)
