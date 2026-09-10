extends SceneTree
## A PICTURE OF THE SHAPE OF THE GROUND. See Mesher._heights.
##
##   WORLD_MAP_OUT=/tmp/ground.png xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 \
##     godot --path <game> --rendering-method gl_compatibility \
##     --script res://tests/ground_look.gd
##
## One chunk of made-up terrain — a diagonal hillside, a straight stair,
## a plateau with a corner, a lone block and a one-wide hole — meshed by
## the real mesher and shot from above by a fixed camera. It exists
## because the ground's shape is a picture, and the only other way to
## look at it is to walk a client up a hill under Xvfb and hope it is
## facing the right way.

const SIZE := 16
var _frames := 0

func _height(x: int, z: int) -> int:
	if z < 7:
		return clampi(x + z - 3, 1, 7)           # a diagonal hillside
	if z == 7 or z == 8:
		return 1                                 # a valley floor
	if x == 3 and z == 11:
		return 3                                 # a lone block on the plateau
	if x == 8 and z == 12:
		return 1                                 # a one-wide hole in it
	if x >= 11:
		return clampi(x - 9, 1, 5)               # a straight stair
	return 2                                     # the plateau

func _initialize() -> void:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * WorldGen.CHUNK_H)
	data.fill(Blocks.AIR)
	for z in SIZE:
		for x in SIZE:
			for y in _height(x, z):
				data[(y * SIZE + z) * SIZE + x] = Blocks.GRASS if y == _height(x, z) - 1 else Blocks.DIRT
	var built: Dictionary = Mesher.new().build(data, {}, 0, 0)
	var root := Node3D.new()
	get_root().add_child(root)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built["opaque"])
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	instance.material_override = mat
	root.add_child(instance)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	root.add_child(env)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(-9, 13, -9), Vector3(8, 2, 8))
	camera.current = true

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false
	var out := OS.get_environment("WORLD_MAP_OUT")
	if out.is_empty():
		out = "/tmp/ground.png"
	get_root().get_texture().get_image().save_png(out)
	print("ground look: ", out)
	return true
