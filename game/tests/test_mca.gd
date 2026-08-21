extends SceneTree
## Standalone check of the Minecraft Anvil importer against a synthetic
## region file (see the repo's world README for how to regenerate it):
##   WORLD_MCA_DIR=<dir with r.0.0.mca> godot --headless -s res://tests/test_mca.gd
##
## The fixture puts, per chunk: stone at mc y 60..63, grass at 64, an oak log
## at local (3, y 65, 5) and a poppy at (5, y 65, 7). With the default
## WORLD_MCA_Y0=40, mc y 64 lands at our y 25.

func _init() -> void:
	var failures := 0
	var mca := McaWorld.new(OS.get_environment("WORLD_MCA_DIR"))
	if not mca.is_valid():
		push_error("FAIL: no region files found")
		quit(1)
		return
	var chunk := mca.read_chunk(0, 0)
	failures += _expect(not chunk.is_empty(), "chunk (0,0) reads")
	if chunk.is_empty():
		quit(1)
		return
	var grass_y := 64 - mca.y0 + 1
	failures += _expect(chunk[WorldGen.idx(0, grass_y, 0)] == Blocks.GRASS,
		"grass at y=%d" % grass_y)
	failures += _expect(chunk[WorldGen.idx(0, grass_y - 1, 0)] == Blocks.STONE,
		"stone under the grass")
	failures += _expect(chunk[WorldGen.idx(0, grass_y - 4, 0)] == Blocks.STONE,
		"stone at the bottom of the slab")
	failures += _expect(chunk[WorldGen.idx(0, 5, 0)] == Blocks.STONE,
		"solid stone underside")
	failures += _expect(chunk[WorldGen.idx(3, grass_y + 1, 5)] == Blocks.LOG,
		"oak log maps to LOG")
	failures += _expect(chunk[WorldGen.idx(5, grass_y + 1, 7)] == Blocks.FLOWER_RED,
		"poppy maps to FLOWER_RED")
	failures += _expect(chunk[WorldGen.idx(8, grass_y + 1, 8)] == Blocks.AIR,
		"air where nothing was placed")
	failures += _expect(chunk[WorldGen.idx(4, 0, 4)] == Blocks.BEDROCK,
		"safety bedrock floor")
	failures += _expect(mca.read_chunk(2, 3).size() > 0, "chunk (2,3) reads")
	failures += _expect(mca.read_chunk(9, 9).is_empty(), "missing chunk is empty")
	# Name mapping spot checks.
	# Birch used to fall through to the generic PLANKS. It has had its own
	# block since, and per-colour glass arrived the same way — this test
	# went on asserting the older, coarser mapping and failing quietly.
	failures += _expect(McaWorld.map_block("minecraft:oak_planks") == Blocks.PLANKS, "oak_planks")
	failures += _expect(McaWorld.map_block("minecraft:birch_planks") == Blocks.BIRCH_PLANKS, "birch_planks")
	failures += _expect(McaWorld.map_block("minecraft:red_wool") == Blocks.WOOL_RED, "red_wool")
	# The tinted glass ids are GLASS_RED plus an offset, in the order the
	# comment beside that constant gives: red orange yellow green blue...
	failures += _expect(McaWorld.map_block("minecraft:glass") == Blocks.GLASS, "plain glass")
	failures += _expect(McaWorld.map_block("minecraft:blue_stained_glass") == Blocks.GLASS_RED + 4, "blue stained glass")
	failures += _expect(McaWorld.map_block("minecraft:oak_sign") == Blocks.AIR, "sign skipped")
	failures += _expect(McaWorld.map_block("minecraft:water") == Blocks.WATER, "water")
	failures += _expect(McaWorld.map_block("minecraft:mystery_future_block") == Blocks.STONE, "unknown -> stone")
	if failures == 0:
		print("MCA importer: all checks passed")
		quit(0)
	else:
		push_error("MCA importer: %d checks FAILED" % failures)
		quit(1)

func _expect(ok: bool, what: String) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
