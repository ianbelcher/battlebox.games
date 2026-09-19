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
## Faces that shaped blocks (slabs, fences, doors) draw without culling
## are counted too, and they overlap each other by design, so the number
## is compared against the SAME world with the lattice flat rather than
## against zero. Bending must not add one.

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
		if bent.open > flat.open:
			failures.append("%s: bending the lattice opened %d edges, e.g. %s"
				% [theme, bent.open - flat.open, bent.samples])
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
	var rim := float(SPAN * 16 + 16)
	for edge: String in edges.keys():
		var pair := edge.split(">")
		if int(edges.get("%s>%s" % [pair[1], pair[0]], 0)) == int(edges[edge]):
			continue
		# The rim of the meshed patch, and the world's floor: what would
		# close those was never meshed.
		var a := _point(pair[0])
		var b := _point(pair[1])
		if (a.y <= 0.001 and b.y <= 0.001) \
				or (a.x <= -rim + 0.001 and b.x <= -rim + 0.001) \
				or (a.x >= rim - 0.001 and b.x >= rim - 0.001) \
				or (a.z <= -rim + 0.001 and b.z <= -rim + 0.001) \
				or (a.z >= rim - 0.001 and b.z >= rim - 0.001):
			continue
		open += 1
		if samples.size() < 4:
			samples.append(edge)
	return {"open": open, "tris": tris, "samples": samples,
		"moved": int(100.0 * float(moved) / maxf(float(seen), 1.0))}

func _point(text: String) -> Vector3:
	var bits := text.substr(1, text.length() - 2).split(", ")
	return Vector3(float(bits[0]), float(bits[1]), float(bits[2]))
