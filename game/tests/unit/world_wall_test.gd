extends TestCase
## The wall around the world, and where the caverns world starts you.

func test_the_edge_of_the_world_is_a_wall_to_the_sky() -> void:
	var gen := WorldGen.new(7, "classic", 64)
	# x = 32 is the last column inside a 64-wide slab: chunk 2, lx 0.
	var data := gen.generate_chunk(2, 0)
	for y in [0, 20, 60, WorldGen.CHUNK_H - 1]:
		equal(int(data[WorldGen.idx(0, y, 0)]), Blocks.BEDROCK,
			"the border column is bedrock at y=%d" % y)
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
