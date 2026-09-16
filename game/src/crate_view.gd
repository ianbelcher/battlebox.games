class_name CrateView
extends Node3D
## Supply crates: spinning wooden boxes with a weapon-colored glow. Walk
## into one and that weapon drops into your hotbar — scavenger style.

var _nodes: Dictionary = {}   # id -> {node, weapon}

func update_crates(payload: Array) -> void:
	var seen := {}
	for entry in payload:
		if not (entry is Array) or entry.size() < 3:
			continue
		var id := int(entry[0])
		seen[id] = true
		if _nodes.has(id):
			continue
		var weapon := int(entry[1])
		var pos: Vector3 = entry[2]
		var node := Node3D.new()
		node.position = pos
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.7, 0.7, 0.7)
		box.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("8a6a42")
		box.material_override = mat
		box.position = Vector3(0, 0.5, 0)
		node.add_child(box)
		var color: Color = GROWTH_COLOR if weapon < 0 \
			else Weapons.spec(weapon).color
		# A GROWTH CRATE HAS NO WEAPON IN IT, so it cannot show one. It
		# shows what it does instead: three boxes stacked, each bigger
		# than the last, which is the only thing on the field that means
		# "this makes you bigger" without a word of text on it.
		var gem := _growth_mark() if weapon < 0 \
			else ItemFactory.build("weapon", weapon)
		gem.scale = Vector3(1.6, 1.6, 1.6)
		gem.position = Vector3(0, 1.25, 0)
		node.add_child(gem)
		# ONE light per crate, and it does not flicker.
		#
		# It used to switch itself off and on as you moved: the renderer
		# only lets so many omni lights affect a given object, so a field
		# full of crates fought each other for the slots. The fix is to
		# make sure only a handful are ever live at once — the light
		# fades out smoothly with distance well before that limit can
		# bite — NOT to replace it with a glowing pole, which is what the
		# last attempt did, and which looked broken.
		#
		# The crate itself is emissive in its weapon's colour, so it
		# still reads as loot from further out than the light reaches,
		# and still reads with dynamic lights switched off entirely.
		var light := OmniLight3D.new()
		light.light_color = color.lightened(0.3)
		light.light_energy = 2.2
		light.omni_range = 6.5
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 22.0
		light.distance_fade_length = 10.0
		light.position = Vector3(0, 1.1, 0)
		node.add_child(light)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.55
		for part in node.find_children("*", "GeometryInstance3D", true, false):
			(part as GeometryInstance3D).visibility_range_end = 140.0
		add_child(node)
		_nodes[id] = {"node": node, "weapon": weapon}
	for id: int in _nodes.keys().duplicate():
		if not seen.has(id):
			_nodes[id].node.queue_free()
			_nodes.erase(id)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _nodes.values():
		var node: Node3D = entry.node
		node.rotation.y += delta * 1.2
		node.get_child(1).position.y = 1.25 + sin(t * 2.0) * 0.12

## THE GROWTH CRATE'S MARK, in Giants' colour: three cubes going up, each
## half again the one below. Built rather than modelled because it is
## three boxes and a modelled asset would be three boxes with a download.
const GROWTH_COLOR := Color("ffb347")

func _growth_mark() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROWTH_COLOR
	mat.emission_enabled = true
	mat.emission = GROWTH_COLOR
	mat.emission_energy_multiplier = 0.8
	var y := 0.0
	for step: float in [0.16, 0.24, 0.36]:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(step, step, step)
		box.mesh = mesh
		box.material_override = mat
		box.position = Vector3(0, y + step * 0.5, 0)
		y += step
		root.add_child(box)
	return root
