class_name Foliage
extends Object
## THE PLANTS ON THE GROUND, built from scratch.
##
## The Kenney nature models this game draws its ground cover with arrive
## with no texture and a flat TEAL albedo — every grass tuft, fern and
## flower stem the same turquoise, which is what "bluish looking things"
## was — and the grass models are a quarter of a block tall, so a reed
## scaled up came out as a wide leafy pancake rather than anything tall.
##
## So the grass and the reeds are made here, as blades: a tapered quad
## per blade, leaning out from a root, coloured darker at the root and
## lighter at the tip, double-sided. Three grasses of different bulk, and
## reeds that are what a reed is — a few near-vertical stalks two and a
## half blocks tall with a brown seed head on some of them. Everything is
## built at block scale (a height of 1.0 is one block) and deterministic
## from a seed, so a chunk looks the same on every client.
##
## The models that stay (flowers, mushrooms, bushes) get their teal
## swapped for a leaf green on load — see recolour().

## The teal the Kenney models arrive painted in, to the digit.
const KENNEY_TEAL := Color(0.4523, 0.9295, 0.8659, 1.0)
const LEAF := Color(0.36, 0.62, 0.27)

static var _cache: Dictionary = {}

## A mesh for a "proc:<kind>" name, cached.
static func build(kind: String) -> Mesh:
	if _cache.has(kind):
		return _cache[kind]
	var mesh: Mesh = null
	match kind:
		"proc:grass":
			mesh = _blades(7, 0.55, 0.85, 0.11, 0.42, 101,
				Color(0.30, 0.52, 0.20), Color(0.58, 0.78, 0.30))
		"proc:clump":
			# THE THICK ONE: twice the blades, taller, wider at the root —
			# a tussock, the thing that makes a field read as uneven.
			mesh = _blades(16, 0.75, 1.15, 0.13, 0.55, 202,
				Color(0.26, 0.48, 0.18), Color(0.55, 0.76, 0.28))
		"proc:fine":
			mesh = _blades(5, 0.3, 0.5, 0.07, 0.3, 303,
				Color(0.34, 0.56, 0.22), Color(0.62, 0.80, 0.34))
		"proc:reeds":
			mesh = _reeds(6, 2.2, 2.8, 404)
	_cache[kind] = mesh
	return mesh

## Blades leaning out from a root. `count` of them, each `h_min..h_max`
## tall and `width` across at the root, their tips spread up to `spread`
## from the centre.
static func _blades(count: int, h_min: float, h_max: float, width: float,
		spread: float, seed: int, root: Color, tip: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in count:
		var angle := rng.randf() * TAU
		var lean := Vector2(cos(angle), sin(angle)) * rng.randf_range(spread * 0.35, spread)
		var h := rng.randf_range(h_min, h_max)
		var base := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
		# Across the blade, perpendicular to its lean, so it faces out.
		var across := Vector3(-lean.y, 0.0, lean.x).normalized() * width * 0.5
		var shade := rng.randf_range(0.85, 1.1)
		_blade(verts, norms, cols, idx, base, Vector3(lean.x, h, lean.y), across,
			root * shade, tip * shade)
	return _mesh(verts, norms, cols, idx)

## Near-vertical stalks, thin, with a seed head on about half of them.
static func _reeds(count: int, h_min: float, h_max: float, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var stalk_root := Color(0.33, 0.45, 0.20)
	var stalk_tip := Color(0.55, 0.66, 0.30)
	var head := Color(0.42, 0.27, 0.13)
	for i in count:
		var angle := rng.randf() * TAU
		var lean := Vector2(cos(angle), sin(angle)) * rng.randf_range(0.05, 0.22)
		var h := rng.randf_range(h_min, h_max)
		var base := Vector3(rng.randf_range(-0.18, 0.18), 0.0, rng.randf_range(-0.18, 0.18))
		var top := Vector3(lean.x, h, lean.y)
		# Two crossed blades per stalk, so it has a face from every side.
		for a: Vector3 in [Vector3(0.045, 0, 0), Vector3(0, 0, 0.045)]:
			_blade(verts, norms, cols, idx, base, top, a, stalk_root, stalk_tip, 0.5)
		if rng.randf() < 0.55:
			_box(verts, norms, cols, idx, base + top - Vector3(0, 0.34, 0),
				Vector3(0.07, 0.34, 0.07), head)
	return _mesh(verts, norms, cols, idx)

## One tapered blade: two quads, root to mid to tip, the mid bent
## outward so it curves, tip width `tip_w` of the root's.
static func _blade(verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, idx: PackedInt32Array, base: Vector3, top: Vector3,
		across: Vector3, root: Color, tip: Color, tip_w := 0.0) -> void:
	var mid := base + top * 0.5 + Vector3(top.x, 0, top.z) * 0.25
	var end := base + top
	var mid_col := root.lerp(tip, 0.5)
	var start := verts.size()
	for p: Array in [[base - across, root], [base + across, root],
			[mid - across * 0.7, mid_col], [mid + across * 0.7, mid_col],
			[end - across * tip_w, tip], [end + across * tip_w, tip]]:
		verts.append(p[0])
		norms.append(Vector3.UP)
		cols.append(p[1])
	for q in [[0, 1, 3, 2], [2, 3, 5, 4]]:
		idx.append_array([start + q[0], start + q[2], start + q[1],
			start + q[0], start + q[3], start + q[2]])

## A little box, centred at `at` in x and z, standing on its base.
static func _box(verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, idx: PackedInt32Array, at: Vector3, size: Vector3,
		col: Color) -> void:
	var h := Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	var lo := at - h
	var hi := at + h + Vector3(0, size.y, 0)
	var corners := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	var faces := [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]
	for f: Array in faces:
		var start := verts.size()
		for c: int in f:
			verts.append(corners[c])
			norms.append(Vector3.UP)
			cols.append(col)
		idx.append_array([start, start + 2, start + 1, start, start + 3, start + 2])

static func _mesh(verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return mesh

## Vertex-coloured, lit like the ground (normals up), drawn from both
## sides: a blade is a sheet with no back.
static var _material: StandardMaterial3D = null

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.roughness = 1.0
		_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _material

## The Kenney models that stay: swap their placeholder teal for a leaf
## green, leave every other colour (petals, caps) alone.
static func recolour(mesh: Mesh) -> void:
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(s)
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_color.is_equal_approx(KENNEY_TEAL):
			var fixed: StandardMaterial3D = mat.duplicate()
			fixed.albedo_color = LEAF
			mesh.surface_set_material(s, fixed)
