extends Node3D
## THE GROUND, PHOTOGRAPHED, with nobody standing on it. Real generated
## terrain, meshed exactly the way a client meshes it, lit and shot from
## a fixed angle — so "does this still look like a stack of boxes" is a
## picture rather than a squint at a screenshot of a whole game.
##
## It takes WORLD_WARP, so the same ground can be photographed bent and
## flat and the two held up against each other. That comparison is the
## only way to judge the number: at 0.25 the bend was there, and the
## hillside still read as boxes.
##
##   # a hillside
##   WORLD_ICON_OUT=/tmp/ground.png xvfb-run -a godot --path game \
##     --resolution 1200x700 --rendering-method gl_compatibility \
##     res://tests/terrain_look.tscn
##
##   # a sheer face, flat for comparison (WORLD_WARP_THEME picks the world)
##   WORLD_WARP_SCENE=wall WORLD_WARP=0 WORLD_ICON_OUT=/tmp/wall.png \
##     xvfb-run -a godot --path game --resolution 1100x640 \
##     --rendering-method gl_compatibility res://tests/terrain_look.tscn
var _out := ""
var _frames := 0

func _ready() -> void:
	_out = OS.get_environment("WORLD_ICON_OUT")
	if _out.is_empty():
		_out = "/tmp/cliff.png"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.72, 0.92)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.environment.ambient_light_energy = 0.55
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -58, 0)
	sun.light_energy = 1.25
	add_child(sun)

	var theme := OS.get_environment("WORLD_WARP_THEME")
	if theme.is_empty():
		theme = "classic"
	var gen := WorldGen.new(4242, theme, 250)
	var chunks := {}
	for cz in range(-2, 3):
		for cx in range(-2, 3):
			chunks[Vector2i(cx, cz)] = gen.generate_chunk(cx, cz)
	if OS.get_environment("WORLD_WARP_SCENE") == "wall":
		# A sheer face of stone with a shelf in front of it, so what the
		# warp does to a VERTICAL surface is the whole picture.
		for key: Vector2i in chunks.keys():
			var data: PackedByteArray = chunks[key]
			data.fill(0)
			for z in 16:
				for x in 16:
					var wx := key.x * 16 + x
					var wz := key.y * 16 + z
					var top := 30
					if wx > 0:
						top = 44 if (wx + (wz / 7)) % 23 > 11 else 38
					for y in top:
						data.encode_u16(WorldGen.bidx(x, y, z), Blocks.STONE if y < top - 1 else Blocks.GRASS)
			chunks[key] = data
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	var warp := Mesher.WARP
	if OS.has_environment("WORLD_WARP"):
		warp = float(OS.get_environment("WORLD_WARP"))
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var neighbors := {}
			for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
					Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1),
					Vector2i(1, -1), Vector2i(-1, 1)]:
				neighbors[off] = chunks[Vector2i(cx, cz) + off]
			var mesher := Mesher.new()
			mesher.warp = warp
			var built: Dictionary = mesher.build(chunks[Vector2i(cx, cz)], neighbors, cx, cz)
			if not built.has("opaque"):
				continue
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built["opaque"])
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = material
			instance.position = Vector3(cx * 16, 0, cz * 16)
			add_child(instance)

	var cam := Camera3D.new()
	var look_at := Vector3(0, float(gen.height_at(0, 0)), 0)
	var eye := Vector3(14, 6, 14)
	if OS.get_environment("WORLD_WARP_SCENE") == "wall":
		look_at = Vector3(2, 36, 0)
		eye = Vector3(-13, 3, 9)
	cam.position = look_at + eye
	cam.look_at_from_position(cam.position, look_at, Vector3.UP)
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()

func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 5:
		return
	get_viewport().get_texture().get_image().save_png(_out)
	print("CLIFF saved %s" % _out)
	get_tree().quit()
