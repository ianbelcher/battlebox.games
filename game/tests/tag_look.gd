extends Node3D
## CAN YOU TELL WHO CANNOT BE TAGGED? Photographed.
##
##     WORLD_ICON_OUT=/tmp/tag.png xvfb-run -a godot --path <game> \
##       --resolution 900x520 --rendering-method gl_compatibility \
##       res://tests/tag_look.tscn
##
## Tag's no-tagging-back rule (TagRules.SAFE_DISTANCE) is invisible unless
## the body says so: It runs up to somebody who has just tipped it, swings,
## and nothing happens. To a five-year-old that is the game being broken,
## not a rule — so the one who is getting away is drawn see-through and
## comes back solid the moment they are clear.
##
## Nothing else here can check that. The material is assigned, the node is
## in the tree, the console is clean, and the two bodies look identical.
## So: a runner, a runner who is still getting away, and an It, in a row.
const SPACING := 2.4
var _frames := 0
var _out := ""

func _ready() -> void:
	_out = OS.get_environment("WORLD_ICON_OUT")
	if _out.is_empty():
		_out = "/tmp/tag.png"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.15, 0.19)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.82, 0.85, 0.92)
	env.environment.ambient_light_energy = 1.1
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 38, 0)
	add_child(sun)

	# Runner, runner-getting-away, It — the three states a body can be in
	# in this mode, in the order they happen to you.
	_body(-SPACING, TagMode.RUNNERS, false, 1.0)
	_body(0.0, TagMode.RUNNERS, true, 1.0)
	_body(SPACING * 1.15, TagMode.IT, false, TagMode.IT_SIZE)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var vp := Vector2(get_viewport().get_visible_rect().size)
	cam.size = (SPACING * 3.6) / maxf(vp.x / maxf(vp.y, 1.0), 0.01)
	cam.position = Vector3(0, 1.5, 10)
	add_child(cam)
	cam.current = true
	print("tag look: runner | getting away | It")

## THE REAL MATERIAL, off Player, rather than something that looks like
## it — a picture of a colour this file invented would prove nothing.
func _body(x: float, _team: int, safe: bool, size: float) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(x, 0, 0)
	holder.rotation_degrees.y = 200.0
	add_child(holder)
	var body := AvatarFactory.build_character({})
	body.scale = Vector3.ONE * Player.AVATAR_SCALE * size
	holder.add_child(body)
	var ap := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and ap.has_animation("idle"):
		ap.play("idle")
	if not safe:
		return
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface,
				Player.faded_skin(mesh.mesh.surface_get_material(surface)))

func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	get_viewport().get_texture().get_image().save_png(_out)
	print("wrote ", _out)
	get_tree().quit()
