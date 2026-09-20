extends TestCase
## TWO BLOCKS THAT DO DIFFERENT THINGS DO NOT SHARE A NAME, and a block
## that is always a cube says so.
##
## The game has two kinds of material and the difference is invisible
## until you build with them: GROUND bends (see Mesher.SMOOTH_BLOCKS — a
## hillside of stone rolls, a step of one level has nothing vertical in
## it), and everything else is drawn as the box it is. Pick the wrong one
## for a pavement and the kerb melts; pick the wrong one for a hillside
## and the hill is a staircase.
##
## So where a material is used both ways it has two ids, and the only
## thing telling them apart in the picker is the name. That makes the
## names load-bearing, which is what this pins down.

## The same thing facing four ways — stairs, a chair, a monitor — shares
## a name on purpose. So do the two blocks at the edge of the office map:
## a window wall and a mullion you cannot dig, which have to read as the
## ones you can or the boundary looks like a different building.
const SAME_THING_TWICE := ["Window Wall", "Mullion"]

func test_no_two_blocks_share_a_name() -> void:
	var seen := {}
	var clashes: Array = []
	for id in Blocks.ID_COUNT:
		var spec := Blocks.info(id)
		var name: String = str(spec.get("name", ""))
		if id == Blocks.AIR or name.is_empty() or name == "Air":
			continue
		if not seen.has(name):
			seen[name] = id
			continue
		if name in SAME_THING_TWICE:
			continue
		# Four facings of one block, which really is one block.
		if int(Blocks.LK_SHAPE[id]) != 0 and int(Blocks.LK_SHAPE[seen[name]]) != 0:
			continue
		clashes.append("%s: %d and %d" % [name, seen[name], id])
	equal(clashes.size(), 0, "blocks sharing a name: %s" % [clashes])
	check(seen.size() > 200, "...out of a lot of blocks (%d)" % seen.size())

func test_every_bending_material_that_is_also_built_has_a_square_twin() -> void:
	for ground: int in Blocks.BUILT_TWIN:
		var twin: int = Blocks.BUILT_TWIN[ground]
		var ground_name: String = Blocks.info(ground)["name"]
		equal(Blocks.info(twin)["name"], "%s Block" % ground_name,
			"the square twin of %s says it is a block" % ground_name)
		equal(Blocks.LK_COLOR[twin], Blocks.LK_COLOR[ground],
			"...and is the same material to look at")
		equal(Blocks.LK_SOLID[twin], Blocks.LK_SOLID[ground],
			"...and the same to walk into")
		equal(Blocks.LK_OPAQUE[twin], Blocks.LK_OPAQUE[ground],
			"...and the same to see through")

func test_the_ground_bends_and_its_twin_does_not() -> void:
	# The whole point of the pair. If this ever comes out the same for
	# both, the split has quietly stopped doing anything and every
	# pavement in the city is back to melting into the verge.
	for ground: int in Blocks.BUILT_TWIN:
		var twin: int = Blocks.BUILT_TWIN[ground]
		check(ground in Mesher.SMOOTH_BLOCKS,
			"%s is ground and bends" % Blocks.info(ground)["name"])
		check(not (twin in Mesher.SMOOTH_BLOCKS),
			"%s is built and does not" % Blocks.info(twin)["name"])

func test_you_can_build_with_both_halves_of_every_pair() -> void:
	# A twin nobody can place is a twin the towns are made of and the
	# players cannot match.
	for ground: int in Blocks.BUILT_TWIN:
		var twin: int = Blocks.BUILT_TWIN[ground]
		check(twin in Blocks.HOTBAR,
			"%s can be placed" % Blocks.info(twin)["name"])
		check(twin in Blocks.picker_category("building"),
			"...and is somewhere in the build picker")

func test_the_twins_are_past_the_wire_format_wall() -> void:
	# 1..255 is frozen: those ids are what a chunk carried when a block
	# was one byte, and a saved world still reads them. Everything new
	# lands above it. See the note on Blocks.TRAP.
	for ground: int in Blocks.BUILT_TWIN:
		check(Blocks.BUILT_TWIN[ground] > 255,
			"%s is a new id" % Blocks.info(Blocks.BUILT_TWIN[ground])["name"])
		check(Blocks.BUILT_TWIN[ground] < Blocks.NEXT_FREE_ID,
			"...and is accounted for in NEXT_FREE_ID")
