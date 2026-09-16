extends Node3D
## HOW A WEAPON LOOKS IN SOMEBODY ELSE'S HAND, photographed.
##
##   WORLD_HELD_CLIP=walk WORLD_ICON_OUT=/tmp/held.png \
##     godot --path <game> --resolution 1400x520 \
##     --rendering-method gl_compatibility res://tests/held_items.tscn
##
## The item in hand is parented to the `arm-right` node and inherits
## whatever the animation is doing to it, and NOTHING else decides which
## way it points. The character pack raises that arm to the horizontal in
## `holding-right` and leaves it hanging in `walk`, `idle` and `sprint` —
## so a weapon that sits correctly in the hand of somebody standing still
## is rotated ninety degrees the moment they take a step, and everybody
## spends most of a round moving.
##
## That is invisible to every other check in this repository: the model
## loads, the node is parented, the animation plays, the console is clean,
## and the gun is pointing at the floor behind its owner. So this lines
## the weapons up in a row in a given pose and takes one picture.

## Which weapons to show, in the order the Tools page has them.
const SHOWN: Array[int] = [13, 0, 1, 15, 9, 2, 12, 14, 19, 18]
const SPACING := 1.9

var _out := ""
var _frames := 0

func _ready() -> void:
	_out = OS.get_environment("WORLD_ICON_OUT")
	if _out.is_empty():
		_out = "/tmp/held.png"
	var clip := OS.get_environment("WORLD_HELD_CLIP")
	if clip.is_empty():
		clip = "walk"

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.11, 0.12, 0.15)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.88)
	env.environment.ambient_light_energy = 1.1
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 38, 0)
	add_child(sun)

	var span := float(SHOWN.size() - 1) * SPACING
	for i in SHOWN.size():
		var who := Node3D.new()
		who.position = Vector3(-span * 0.5 + float(i) * SPACING, 0.0, 0)
		# Turned a little off square, so a weapon pointing BACKWARDS is
		# obvious rather than hidden behind the body.
		who.rotation_degrees.y = 210.0
		add_child(who)
		# IN THE TREE FIRST: the attachment reads the rig's GLOBAL scale to
		# cancel it, exactly as the game does, and a node outside the tree
		# does not have one.
		_dress(who, SHOWN[i], clip)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# A Camera3D's ortho `size` is its VERTICAL extent, and what has to fit
	# here is the horizontal row — so it is the span divided by the aspect,
	# or ten characters come out six pixels tall in the middle of an empty
	# picture, which is what the first run of this produced.
	var vp := Vector2(get_viewport().get_visible_rect().size)
	cam.size = (span + SPACING) / maxf(vp.x / maxf(vp.y, 1.0), 0.01)
	cam.position = Vector3(0, 0.85, 14)
	add_child(cam)
	cam.current = true
	print("held items: %d weapons in '%s'" % [SHOWN.size(), clip])

## THE REAL AVATAR AND THE REAL ATTACHMENT, both of them, or the picture
## is of something the game does not do. AvatarFactory owns the scale and
## the 180-degree turn the pack needs; Player owns where in the arm a held
## thing sits and which way it points.
func _dress(holder: Node3D, weapon_id: int, clip: String) -> void:
	var body := AvatarFactory.build_character({})
	body.scale = Vector3.ONE * Player.AVATAR_SCALE
	holder.add_child(body)
	var ap := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and ap.has_animation(clip):
		ap.play(clip)
		# A pose, not a movie: parked part way through the stride, so the
		# arm is somewhere typical rather than at the top of its swing.
		ap.seek(ap.get_animation(clip).length * 0.25, true)
		ap.pause()
	var arm: Node3D = body.find_child("arm-right", true, false)
	if arm == null:
		return
	var item := ItemFactory.build("weapon", weapon_id)
	# The same cancellation Player._refresh_hand does: the item comes out
	# the size it would be in the world rather than the size the rig is.
	var rig := maxf(arm.get_parent_node_3d().global_basis.get_scale().y, 0.01)
	item.scale = Vector3.ONE / rig
	item.position = Player.HAND_OFFSET
	# WORLD_HELD_RAW=1 shows what it looked like before the arm's pose was
	# taken into account at all — which is the picture that says whether
	# the correction is doing anything.
	item.rotation_degrees = Vector3.ZERO \
		if OS.get_environment("WORLD_HELD_RAW") == "1" \
		else Player.hand_tilt_degrees(clip)
	arm.add_child(item)

func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	get_viewport().get_texture().get_image().save_png(_out)
	print("wrote ", _out)
	get_tree().quit()
