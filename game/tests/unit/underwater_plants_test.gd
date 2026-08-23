extends TestCase
## Water flows THROUGH a plant, rather than closing a box around it.
##
## Seaweed in Isles came out inside a blue cube. A plant standing in water
## is a cell that is not itself water, so every neighbouring water block
## drew a face pointing at it — six of them, a complete water-skinned box,
## which read as the plant sitting in a little air pocket at the bottom of
## the sea.
##
## Worth a test because nothing else can see it. It is not an error, not a
## crash and not a wrong block: the world is correct and the picture of it
## is wrong, and the only other way to find out is for somebody to swim
## down and look.

const SIZE := 16

func _at(x: int, y: int, z: int) -> int:
	return (y * SIZE + z) * SIZE + x

## A chunk of solid water from the floor to `depth`, with one block
## optionally swapped for something else in the middle of it.
func _sea(depth: int, middle := -1) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * WorldGen.CHUNK_H)
	data.fill(Blocks.AIR)
	for y in depth:
		for z in SIZE:
			for x in SIZE:
				data[_at(x, y, z)] = Blocks.WATER
	if middle >= 0:
		data[_at(8, depth / 2, 8)] = middle
	return data

## How many water vertices the mesher produced. `build` returns a surface
## as a Mesh.ARRAY_MAX-sized array, so the vertices are one slot inside it
## rather than a key of their own.
func _water_faces(data: PackedByteArray) -> int:
	var built: Dictionary = Mesher.new().build(data, {}, 0, 0)
	if not built.has("trans"):
		return 0
	var arrays: Array = built["trans"]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size()

func test_a_plant_in_the_sea_adds_no_water_faces() -> void:
	var plain := _water_faces(_sea(20))
	var weedy := _water_faces(_sea(20, Blocks.FERN))
	check(plain > 0, "the sea has a surface, so there is something to compare against")
	equal(weedy, plain,
		"a submerged plant must not make the water grow faces around it")

func test_an_air_pocket_in_the_sea_still_gets_its_walls() -> void:
	# The opposite case, so the rule above cannot be satisfied by simply
	# never drawing internal faces. A hole in the water IS a hole and has
	# to be walled, or you would see straight out of the sea through it.
	var plain := _water_faces(_sea(20))
	var holed := _water_faces(_sea(20, Blocks.AIR))
	check(holed > plain,
		"an air pocket is a real hole and the water still closes around it")

func test_a_rock_in_the_sea_hides_the_water_behind_it() -> void:
	# And an opaque neighbour takes faces AWAY, which is the third case
	# the same branch decides.
	var plain := _water_faces(_sea(20))
	var stony := _water_faces(_sea(20, Blocks.STONE))
	equal(stony, plain, "a solid block in the water shows no water faces either")
