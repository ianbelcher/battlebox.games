extends TestCase
## FOLIAGE HAS NO ROOTS OF ITS OWN. A tuft of grass is a block that
## happens to be sitting on another one, and when the ground under it is
## dug, shot, blasted or bored away it has to come out too — otherwise it
## is left standing in mid-air, which is what shooting the ground under a
## reed bed used to leave behind.
##
## See TerrainSim.rooted_above; every path that clears a cell goes
## through it.

func _world(blocks: Dictionary) -> Callable:
	return func(pos: Vector3i) -> int:
		return int(blocks.get(pos, Blocks.AIR))

func test_the_plant_on_a_cleared_block_comes_out_with_it() -> void:
	var blocks := {Vector3i(4, 9, 4): Blocks.TALL_GRASS}
	var pulled := TerrainSim.rooted_above([Vector3i(4, 8, 4)], _world(blocks))
	equal(pulled, [Vector3i(4, 9, 4)], "the tuft over the cleared block comes out")

func test_bare_ground_pulls_nothing() -> void:
	var blocks := {Vector3i(4, 9, 4): Blocks.STONE}
	equal(TerrainSim.rooted_above([Vector3i(4, 8, 4)], _world(blocks)), [],
		"a block with stone over it is just a block with stone over it")
	equal(TerrainSim.rooted_above([Vector3i(9, 2, 9)], _world({})), [],
		"and open air over it pulls nothing")

func test_a_stack_of_them_comes_out_from_the_bottom() -> void:
	# Bamboo and cattails stand more than one high.
	var blocks := {
		Vector3i(2, 5, 2): Blocks.BAMBOO,
		Vector3i(2, 6, 2): Blocks.BAMBOO,
		Vector3i(2, 7, 2): Blocks.BAMBOO,
	}
	var pulled := TerrainSim.rooted_above([Vector3i(2, 4, 2)], _world(blocks))
	equal(pulled.size(), 3, "the whole stalk comes out, not just its foot")

func test_every_cleared_cell_is_asked() -> void:
	var blocks := {
		Vector3i(0, 1, 0): Blocks.FERN,
		Vector3i(3, 1, 0): Blocks.FLOWER_RED,
	}
	var pulled := TerrainSim.rooted_above(
		[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(3, 0, 0)], _world(blocks))
	equal(pulled.size(), 2, "a blast that clears three cells takes both plants")
