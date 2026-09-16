class_name OverviewMap
## THE WHOLE WORLD AT A GLANCE — the low-resolution backdrop the radar
## draws under the chunks it actually has, so the map shows the shape of
## the world beyond what is rendered even on a slow machine.
##
## 192x192 samples at four blocks each, built once on the server from the
## PURE terrain function: no chunk is generated for it, which is the only
## reason it can cover the whole slab at boot. An imported Minecraft world
## has no pure function and simply goes without.
##
## Here rather than on the world node because it is a fact about a MAP —
## what a column reads as from above — and the world node is the wire
## protocol, already at the size ceiling the style test enforces.

const SIDE := 192
const BLOCKS_PER_SAMPLE := 4

## The sample a world position falls in, or -1 off the edge of the grid.
static func index_of(wx: int, wz: int) -> int:
	var ox := wx / BLOCKS_PER_SAMPLE + SIDE / 2
	var oz := wz / BLOCKS_PER_SAMPLE + SIDE / 2
	if ox < 0 or ox >= SIDE or oz < 0 or oz >= SIDE:
		return -1
	return oz * SIDE + ox

static func build(gen: WorldGen, theme: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SIDE * SIDE)
	for oz in SIDE:
		for ox in SIDE:
			var wx := (ox - SIDE / 2) * BLOCKS_PER_SAMPLE
			var wz := (oz - SIDE / 2) * BLOCKS_PER_SAMPLE
			out[oz * SIDE + ox] = _sample(gen, theme, wx, wz)
	return out

static func _sample(gen: WorldGen, theme: String, wx: int, wz: int) -> int:
	# OUTSIDE THE WORLD IS NOTHING. The generator is a pure function and
	# will happily invent terrain forever, so without this the radar drew
	# a full island — grass, beaches, snow — all round a 50-block world,
	# and on the space map it drew grass and ice over what should be
	# black. Air reads as the radar's background, which is what "off the
	# map" should look like.
	if not gen.in_bounds(wx, wz):
		return Blocks.AIR
	# AN INTERIOR HAS NO HEIGHT WORTH DRAWING. The office floor plate is
	# flat by construction, so reading it by height paints the whole slab
	# one colour — it came out solid blue, being three blocks up and
	# therefore "under the sea". What a radar can usefully say about a
	# building is its PLAN: where the corridors run, where the core is,
	# and what kind of room each lot holds.
	if theme == "office":
		return gen.office_overview_at(wx, wz)
	var h := gen.height_at(wx, wz)
	h -= gen.lake_depth_at(wx, wz, h)
	return by_height(theme, h)

## What a column of this height reads as. Per THEME: the space map has no
## grass and no snow on it, and painting it with the classic island
## palette is why it came out looking like Earth.
static func by_height(theme: String, h: int) -> int:
	match theme:
		"desert":
			return Blocks.SAND if h > WorldGen.SEA_LEVEL else Blocks.WATER
		"space":
			# Grey regolith, and the "sea" is the void between craters.
			return Blocks.STONE if h > WorldGen.SEA_LEVEL else Blocks.AIR
		"sky":
			return Blocks.GRASS if h > WorldGen.SEA_LEVEL else Blocks.AIR
	if h <= WorldGen.SEA_LEVEL:
		return Blocks.WATER
	if h <= WorldGen.SEA_LEVEL + 2:
		return Blocks.SAND
	if h > WorldGen.SEA_LEVEL + 22:
		return Blocks.SNOW
	return Blocks.GRASS
