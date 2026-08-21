extends Node3D
## Renders a weapon's HELD MODEL to its hotbar icon.
##
##   WORLD_ICON_IDS=18,19 WORLD_ICON_OUT=<abs>/assets/ui/weapons \
##     godot --path <game> --resolution 256x256 res://tests/weapon_icons.tscn
##
## The icons are PNGs at assets/ui/weapons/w<id>.png, and every weapon
## that has a real model had one drawn from it. The two newest gadgets
## did not, so they fell back to BlockIcon's hand-drawn shapes and looked
## like nothing in particular next to the rest. This renders them the
## same way: the actual model, lit the same, framed the same.
##
## Needs a real window — a headless run has no renderer to draw with.

var _ids: Array = []
var _out := ""
var _at := 0
var _frames := 0
var _holder: Node3D

func _ready() -> void:
	_out = OS.get_environment("WORLD_ICON_OUT")
	if _out.is_empty():
		_out = "/tmp"
	var raw := OS.get_environment("WORLD_ICON_IDS")
	for part in (raw if not raw.is_empty() else "18,19").split(","):
		if part.strip_edges().is_valid_int():
			_ids.append(part.strip_edges().to_int())
	# Transparent, side-on, filling the frame: the icons already in the
	# set are cut-outs of the weapon in profile, and a new one that is a
	# three-quarter view on a dark plate reads as a different game.
	get_viewport().transparent_bg = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0, 0, 0, 0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.environment.ambient_light_energy = 0.85
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.5
	add_child(key)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.15
	cam.position = Vector3(1.8, 0.28, 0.0)
	# Into the tree FIRST: look_at needs a global transform, and calling
	# it on a node that is not in the tree yet fails.
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	_holder = Node3D.new()
	add_child(_holder)
	_load(0)

func _load(index: int) -> void:
	for child in _holder.get_children():
		child.queue_free()
	if index >= _ids.size():
		return
	var model := ItemFactory.build("weapon", int(_ids[index]))
	# Held models point down -Z; the camera sits on +X, so this is a
	# straight profile.
	model.rotation_degrees = Vector3.ZERO
	_holder.add_child(model)
	# FRAME IT FROM ITS OWN BOUNDS. Every weapon is modelled around a
	# different origin — built to sit in a hand, not in a picture — so a
	# fixed scale and offset leaves one filling the icon and the next
	# stranded in a corner.
	var bounds := _bounds_of(model)
	if bounds.size.length() > 0.001:
		var reach := maxf(maxf(bounds.size.y, bounds.size.z), 0.001)
		model.scale = Vector3.ONE * (0.85 / reach)
		var mid := bounds.position + bounds.size * 0.5
		model.position = -mid * model.scale.x

## The combined AABB of every mesh under a node, in the node's own space.
func _bounds_of(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var box := vi.get_aabb()
		# Into the model's space, so nested offsets are accounted for.
		var local := root.global_transform.affine_inverse() * vi.global_transform
		box = local * box
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out

func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	_frames = 0
	if _at >= _ids.size():
		get_tree().quit(0)
		return
	var image := get_viewport().get_texture().get_image()
	var path := "%s/w%d.png" % [_out, int(_ids[_at])]
	if image.save_png(path) == OK:
		print("wrote %s" % path)
	else:
		push_error("could not write %s" % path)
	_at += 1
	_load(_at)
