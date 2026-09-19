extends SceneTree
## IS THE GROUND ACTUALLY CLOSED? Nine chunks of real generated terrain
## per theme, meshed with all their neighbours and joined into one world,
## and then every triangle edge counted. An edge with nothing on its
## other side is a hole you can see the sky through.
##
## The unit suite checks the same property on hand-made ground (see
## ground_shape_test), which is where the rules are pinned down. This is
## the other half: terrain nobody designed, with caves, overhangs, water,
## beaches, trees and whatever the generator felt like, at the scale
## where a rule that is right in nine cases out of ten still leaves a
## hole every few hundred blocks.
##
## It exists because the lattice bends (Mesher.WARP). Every corner where
## blocks meet is shared by up to eight of them, each drawing its own
## faces to it, and a rule that lets one of them move a corner while
## another draws it square does not error, log, or show up in anything
## but a screenshot of that exact spot.
##
## Two kinds of block draw faces that nothing is supposed to match, and
## both are deliberate: a slab or a fence emits all six sides of each of
## its little boxes without culling, and a block that is SOLID BUT NOT
## OPAQUE — a glowstone, a pane of glass — has its neighbours draw into
## it while it culls against them. Edges touching either are left out of
## the count, and what remains has to be nothing at all.

const THEMES := ["classic", "desert", "isles", "caverns"]
const SPAN := 1      # chunks either side of the middle one
## The eight neighbours a chunk is meshed with, as ChunkView sends them.
const AROUND := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

func _init() -> void:
	var failures: Array = []
	for theme: String in THEMES:
		var bent := _open_edges(theme, Mesher.WARP)
		var flat := _open_edges(theme, 0.0)
		print("WATERTIGHT %s: %d open edges bent, %d flat (%d triangles, %d%% of corners moved)"
			% [theme, bent.open, flat.open, bent.tris, bent.moved])
		if bent.open > 0 or flat.open > 0:
			failures.append("%s: %d edges with nothing on the other side (%d with the lattice flat), e.g. %s"
				% [theme, bent.open, flat.open, bent.samples])
		if bent.moved < 20 and theme != "isles":
			failures.append("%s: only %d%% of corners moved — is the warp reaching the world?"
				% [theme, bent.moved])
	if failures.is_empty():
		print("WATERTIGHT: ok")
		quit(0)
		return
	for line: String in failures:
		print("WATERTIGHT FAILED %s" % line)
	quit(1)

## One world's worth: how many edges have nothing on the other side, how
## many triangles there were, and how much of the lattice actually moved.
func _open_edges(theme: String, warp: float) -> Dictionary:
	var gen := WorldGen.new(4242, theme, 250)
	var chunks := {}
	for cz in range(-SPAN - 1, SPAN + 2):
		for cx in range(-SPAN - 1, SPAN + 2):
			chunks[Vector2i(cx, cz)] = gen.generate_chunk(cx, cz)
	_chunks = chunks
	var edges := {}
	var tris := 0
	var moved := 0
	var seen := 0
	for cz in range(-SPAN, SPAN + 1):
		for cx in range(-SPAN, SPAN + 1):
			var here := Vector2i(cx, cz)
			var neighbors := {}
			for off: Vector2i in AROUND:
				neighbors[off] = chunks[here + off]
			var mesher := Mesher.new()
			mesher.warp = warp
			var built: Dictionary = mesher.build(chunks[here], neighbors, cx, cz)
			for key: String in ["opaque", "roof"]:
				if not built.has(key):
					continue
				var arrays: Array = built[key]
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				tris += index.size() / 3
				var origin := Vector3(cx * 16, 0, cz * 16)
				for vert in verts:
					seen += 1
					var frac: float = vert.y - floorf(vert.y)
					if frac > 0.0005 and frac < 0.9995:
						moved += 1
				for i in range(0, index.size(), 3):
					for k in 3:
						var a := (verts[index[i + k]] + origin).snapped(Vector3.ONE * 0.001)
						var b := (verts[index[i + (k + 1) % 3]] + origin).snapped(Vector3.ONE * 0.001)
						var edge := "%s>%s" % [a, b]
						edges[edge] = int(edges.get(edge, 0)) + 1
	var open := 0
	var samples: Array = []
	# The patch runs from -SPAN chunks to SPAN + 1 chunks: its two rims
	# are not the same number, and calling them both SPAN * 16 + 16 left
	# every edge on the low side counted as a hole.
	var low := float(-SPAN * 16)
	var high := float((SPAN + 1) * 16)
	for edge: String in edges.keys():
		var pair := edge.split(">")
		if int(edges.get("%s>%s" % [pair[1], pair[0]], 0)) == int(edges[edge]):
			continue
		# The rim of the meshed patch, and the world's floor: what would
		# close those was never meshed.
		var a := _point(pair[0])
		var b := _point(pair[1])
		if (a.y <= 0.001 and b.y <= 0.001) \
				or (a.x <= low + 0.001 and b.x <= low + 0.001) \
				or (a.x >= high - 0.001 and b.x >= high - 0.001) \
				or (a.z <= low + 0.001 and b.z <= low + 0.001) \
				or (a.z >= high - 0.001 and b.z >= high - 0.001):
			continue
		if _drawn_loose_beside(a, b):
			continue
		open += 1
		if samples.size() < 4:
			samples.append(edge)
	return {"open": open, "tris": tris, "samples": samples,
		"moved": int(100.0 * float(moved) / maxf(float(seen), 1.0))}

## The world this run is counting, for _drawn_loose_beside.
var _chunks: Dictionary = {}

## Is there a block beside this edge that draws faces nobody matches? A
## slab, a fence, a door — every side of every box, uncalled — or a solid
## block that is not opaque, which its neighbours draw into while it culls
## against them. Both are on purpose, and both leave edges over.
func _drawn_loose_beside(a: Vector3, b: Vector3) -> bool:
	var middle := (a + b) * 0.5
	for dx in [-1, 0]:
		for dy in [-1, 0]:
			for dz in [-1, 0]:
				var block := _block_at(floori(middle.x) + dx,
					floori(middle.y + 0.5) + dy, floori(middle.z) + dz)
				if block == Blocks.AIR:
					continue
				if int(Blocks.LK_SHAPE[block]) != 0:
					return true
				if Blocks.LK_SOLID[block] == 1 and Blocks.LK_OPAQUE[block] != 1:
					return true
	return false

func _block_at(wx: int, wy: int, wz: int) -> int:
	if wy < 0 or wy >= WorldGen.CHUNK_H:
		return Blocks.AIR
	var cpos := Vector2i(floori(float(wx) / 16.0), floori(float(wz) / 16.0))
	var data: PackedByteArray = _chunks.get(cpos, PackedByteArray())
	if data.is_empty():
		return Blocks.AIR
	return data.decode_u16(WorldGen.bidx(posmod(wx, 16), wy, posmod(wz, 16)))

func _point(text: String) -> Vector3:
	var bits := text.substr(1, text.length() - 2).split(", ")
	return Vector3(float(bits[0]), float(bits[1]), float(bits[2]))
