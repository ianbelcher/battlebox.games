class_name ItemFactory
## Chunky procedural 3D models for weapons and blocks — used by supply
## crates, the hand viewmodel and other players' held items. Built like the
## critters: primitive meshes, no assets.

static func _mat(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.4
	return mat

static func _box(size: Vector3, color: Color, pos: Vector3, emissive := false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = _mat(color, emissive)
	instance.position = pos
	return instance

static func _cyl(top: float, bottom: float, height: float, color: Color,
		pos: Vector3, rot := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	instance.mesh = mesh
	instance.material_override = _mat(color, emissive)
	instance.position = pos
	instance.rotation_degrees = rot
	return instance

## An item model, roughly 0.5-0.8 units long, origin at the grip.
## The markings that tell one full block from another in your hand. A
## held bookshelf should read as a bookshelf, not as a brown cube — the
## picker icons have always drawn this detail, the thing in your hand
## didn't. Thin plates sit just proud of each face; anything not listed
## keeps its plain cube, which is right for stone and wool.
## Bookshelf has no Blocks constant — it lives in the Minecraft-style
## range mapped by mca.gd, which calls it 132.
const BOOKSHELF := 132

static func _block_detail(root: Node3D, id: int, color: Color) -> void:
	const S := 0.3          # the cube's side
	const OUT := 0.152      # just outside the face, so it never z-fights
	var dark := color.darkened(0.34)
	var lite := color.lightened(0.22)
	# Shelves of books: three bands on all four sides.
	if id == BOOKSHELF:
		for i in 3:
			var y := 0.1 - S * 0.33 + S * 0.33 * i
			for spec in [[Vector3(0, y, OUT), Vector3(S, 0.055, 0.005)],
					[Vector3(0, y, -OUT), Vector3(S, 0.055, 0.005)],
					[Vector3(OUT, y, 0), Vector3(0.005, 0.055, S)],
					[Vector3(-OUT, y, 0), Vector3(0.005, 0.055, S)]]:
				root.add_child(_box(spec[1], [Color("c96b4a"), Color("8a5fb0"),
					Color("4a9df8")][i], spec[0]))
		return
	# Planks: horizontal seams.
	if id in [Blocks.PLANKS, Blocks.BIRCH_PLANKS, Blocks.DARK_PLANKS,
			Blocks.CHERRY_PLANKS, Blocks.WARPED_PLANKS, Blocks.CRIMSON_PLANKS,
			Blocks.MANGROVE_PLANKS]:
		for i in 2:
			var y := 0.1 - S * 0.2 + S * 0.4 * i
			root.add_child(_box(Vector3(S, 0.012, 0.005), dark, Vector3(0, y, OUT)))
			root.add_child(_box(Vector3(S, 0.012, 0.005), dark, Vector3(0, y, -OUT)))
		return
	# Logs: bark ridges round the sides, rings on the cut ends.
	if id in [Blocks.LOG, Blocks.WARPED_STEM, Blocks.BAMBOO_BLOCK]:
		for i in 3:
			var x := -S * 0.3 + S * 0.3 * i
			root.add_child(_box(Vector3(0.012, S, 0.005), dark, Vector3(x, 0.1, OUT)))
			root.add_child(_box(Vector3(0.012, S, 0.005), dark, Vector3(x, 0.1, -OUT)))
		root.add_child(_box(Vector3(0.12, 0.005, 0.12), dark, Vector3(0, 0.1 + OUT, 0)))
		return
	# Bricks: courses with staggered joints.
	if id == Blocks.BRICK:
		for i in 3:
			var y := 0.1 - S * 0.34 + S * 0.34 * i
			root.add_child(_box(Vector3(S, 0.01, 0.005), lite, Vector3(0, y, OUT)))
			root.add_child(_box(Vector3(S, 0.01, 0.005), lite, Vector3(0, y, -OUT)))
			var off: float = 0.06 if i % 2 == 0 else -0.06
			root.add_child(_box(Vector3(0.01, S * 0.34, 0.005), lite,
				Vector3(off, y + S * 0.17, OUT)))
		return
	# Crafting table: a gridded work surface and tools on the side.
	if id == Blocks.CRAFTING_TABLE:
		root.add_child(_box(Vector3(0.3, 0.006, 0.012), dark, Vector3(0, 0.1 + OUT, 0)))
		root.add_child(_box(Vector3(0.012, 0.006, 0.3), dark, Vector3(0, 0.1 + OUT, 0)))
		root.add_child(_box(Vector3(0.09, 0.09, 0.005), dark, Vector3(0, 0.13, OUT)))
		return
	# Furnace: a dark mouth with a lit fire in it.
	if id == Blocks.FURNACE:
		root.add_child(_box(Vector3(0.16, 0.12, 0.005), Color("2a2a30"),
			Vector3(0, 0.06, -OUT)))
		root.add_child(_box(Vector3(0.1, 0.04, 0.008), Color("ff8a3d"),
			Vector3(0, 0.03, -OUT), true))
		return
	# Chest: lid seam and a latch on the front.
	if id == Blocks.CHEST:
		root.add_child(_box(Vector3(S, 0.014, 0.006), dark, Vector3(0, 0.17, -OUT)))
		root.add_child(_box(Vector3(S, 0.014, 0.006), dark, Vector3(0, 0.17, OUT)))
		root.add_child(_box(Vector3(0.05, 0.06, 0.01), Color("d8c37a"),
			Vector3(0, 0.15, -OUT)))
		return
	# Pumpkin and melon: carved ribs.
	if id == Blocks.PUMPKIN:
		for i in 3:
			var x := -S * 0.3 + S * 0.3 * i
			root.add_child(_box(Vector3(0.01, S, 0.005), dark, Vector3(x, 0.1, -OUT)))
			root.add_child(_box(Vector3(0.01, S, 0.005), dark, Vector3(x, 0.1, OUT)))
		root.add_child(_box(Vector3(0.05, 0.05, 0.01), Color("4a7a2a"),
			Vector3(0, 0.1 + OUT, 0)))
		return

static func build(kind: String, id: int) -> Node3D:
	var root := Node3D.new()
	if kind == "block":
		# Hold the actual thing, not an anonymous colored cube: plants are
		# little crossed sprigs, torches glow, slabs are half-height,
		# stairs are stepped, fences are posts — full blocks keep their
		# distinct top color like the world mesh does.
		var color := Blocks.color_of(id)
		var shape := Blocks.shape_of(id)
		if id == Blocks.TORCH:
			root.add_child(_box(Vector3(0.05, 0.26, 0.05), Color("8a6242"), Vector3(0, 0.1, 0)))
			root.add_child(_box(Vector3(0.07, 0.07, 0.07), Color("ffd166"), Vector3(0, 0.27, 0), true))
			return root
		if Blocks.is_cross(id):
			for angle in [45.0, -45.0]:
				var sprig := _box(Vector3(0.24, 0.3, 0.02), color, Vector3(0, 0.12, 0))
				sprig.rotation_degrees.y = angle
				root.add_child(sprig)
			return root
		match shape:
			"slab":
				root.add_child(_box(Vector3(0.3, 0.15, 0.3), color, Vector3(0, 0.05, 0)))
			"carpet":
				root.add_child(_box(Vector3(0.3, 0.05, 0.3), color, Vector3(0, 0.02, 0)))
			"stairs":
				root.add_child(_box(Vector3(0.3, 0.15, 0.3), color, Vector3(0, 0.04, 0)))
				root.add_child(_box(Vector3(0.3, 0.15, 0.15), color.lightened(0.06), Vector3(0, 0.19, 0.075)))
			"fence":
				root.add_child(_box(Vector3(0.06, 0.32, 0.06), color, Vector3(0, 0.12, 0)))
				root.add_child(_box(Vector3(0.3, 0.05, 0.04), color.lightened(0.1), Vector3(0, 0.16, 0)))
				root.add_child(_box(Vector3(0.3, 0.05, 0.04), color.lightened(0.1), Vector3(0, 0.04, 0)))
			"wall":
				root.add_child(_box(Vector3(0.14, 0.3, 0.14), color, Vector3(0, 0.11, 0)))
				root.add_child(_box(Vector3(0.3, 0.24, 0.1), color.darkened(0.1), Vector3(0, 0.08, 0)))
			"pane":
				root.add_child(_box(Vector3(0.3, 0.3, 0.03), color.lightened(0.15), Vector3(0, 0.12, 0)))
			_:
				var glow := Blocks.emit_of(id) > 0.6
				root.add_child(_box(Vector3(0.3, 0.3, 0.3), color, Vector3(0, 0.1, 0), glow))
				var top := Blocks.top_color_of(id)
				if top != color:
					root.add_child(_box(Vector3(0.31, 0.02, 0.31), top, Vector3(0, 0.26, 0)))
				_block_detail(root, id, color)
		return root
	if kind == "structure":
		root.add_child(_box(Vector3(0.34, 0.2, 0.3), Structures.spec(id).color, Vector3(0, 0.06, 0)))
		root.add_child(_box(Vector3(0.4, 0.1, 0.36), Structures.spec(id).color.darkened(0.3), Vector3(0, 0.2, 0)))
		return root
	# Kenney Blaster Kit (CC0): real models for the shooters. Forward is
	# -Z to match the muzzle convention everywhere else in the game.
	# Real models beat hand-stacked boxes every time. 18 takes the blaster
	# the retired bridge gun used to have; 19 shares the grenade with the
	# paint bomb, which is exactly what a smoke canister looks like.
	const KENNEY_WEAPONS := {0: "blaster-g", 1: "blaster-m", 2: "blaster-i",
		3: "blaster-b", 4: "blaster-c", 8: "grenade-a",
		9: "blaster-h", 14: "blaster-k", 15: "blaster-q",
		18: "blaster-o", 19: "grenade-a"}
	if kind == "weapon" and KENNEY_WEAPONS.has(id):
		var scene: PackedScene = load("res://assets/models/%s.glb" % KENNEY_WEAPONS[id])
		if scene != null:
			var inst: Node3D = scene.instantiate()
			inst.rotation_degrees = Vector3(0, 180, 0)
			inst.scale = Vector3.ONE * 0.8
			inst.position = Vector3(0, 0.02, 0)
			root.add_child(inst)
			return root
	match id:
		0:  # Blaster: compact pistol with shroud + bead sight
			root.add_child(_box(Vector3(0.09, 0.12, 0.3), Color("6c6f78"), Vector3(0, 0.08, -0.1)))
			root.add_child(_box(Vector3(0.11, 0.06, 0.16), Color("52555e"), Vector3(0, 0.1, -0.18)))
			root.add_child(_box(Vector3(0.07, 0.14, 0.09), Color("4a4c54"), Vector3(0, -0.02, 0.02)))
			root.add_child(_box(Vector3(0.02, 0.03, 0.02), Color("ffe08a"), Vector3(0, 0.16, -0.2), true))
			root.add_child(_cyl(0.035, 0.035, 0.16, Color("ffe08a"), Vector3(0, 0.08, -0.31), Vector3(90, 0, 0), true))
		1:  # Bazooka: shoulder tube with grip, exhaust bell and sight
			root.add_child(_cyl(0.09, 0.09, 0.7, Color("5f6a52"), Vector3(0, 0.1, -0.1), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.12, 0.12, 0.12, Color("ff7a3d"), Vector3(0, 0.1, -0.46), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.09, 0.13, 0.12, Color("47503d"), Vector3(0, 0.1, 0.3), Vector3(90, 0, 0)))
			root.add_child(_box(Vector3(0.07, 0.14, 0.08), Color("35363c"), Vector3(0, -0.03, 0.0)))
			root.add_child(_box(Vector3(0.03, 0.08, 0.03), Color("8a9478"), Vector3(0, 0.22, -0.18)))
		2:  # Grapple: launcher with a three-prong hook and rope drum
			root.add_child(_box(Vector3(0.1, 0.12, 0.24), Color("6c6f78"), Vector3(0, 0.06, -0.04)))
			root.add_child(_cyl(0.02, 0.05, 0.16, Color("c9b3ff"), Vector3(0, 0.1, -0.24), Vector3(90, 0, 0)))
			for hook_a in [0.0, 120.0, 240.0]:
				var prong := _box(Vector3(0.025, 0.09, 0.025), Color("d8cfff"),
					Vector3(0, 0.1, -0.34))
				prong.rotation_degrees = Vector3(25, 0, hook_a)
				root.add_child(prong)
			root.add_child(_cyl(0.06, 0.06, 0.08, Color("4a4c54"), Vector3(0, 0.14, 0.06), Vector3(0, 0, 90)))
		9:  # Napalm: red rocket with tail fins
			root.add_child(_cyl(0.07, 0.07, 0.5, Color("b33a2a"), Vector3(0, 0.1, -0.1), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.0, 0.07, 0.14, Color("ffd166"), Vector3(0, 0.1, -0.42), Vector3(90, 0, 0), true))
			for fin_a in [0.0, 90.0, 180.0, 270.0]:
				var fin := _box(Vector3(0.02, 0.1, 0.12), Color("7d251a"), Vector3(0, 0.1, 0.12))
				fin.rotation_degrees = Vector3(0, 0, fin_a + 45.0)
				root.add_child(fin)
		12:  # Digger: a real auger — motor housing, ribbed shaft, spiral
			# flighting and a bit. It used to be a cone on a box.
			root.add_child(_box(Vector3(0.15, 0.16, 0.22), Color("6b573a"), Vector3(0, 0.06, 0.06)))
			root.add_child(_box(Vector3(0.17, 0.07, 0.1), Color("4a4c54"), Vector3(0, 0.13, 0.04)))
			root.add_child(_cyl(0.055, 0.055, 0.34, Color("8a7654"), Vector3(0, 0.06, -0.2), Vector3(90, 0, 0)))
			# Spiral flighting: discs stepping round the shaft.
			for turn in range(6):
				var blade := _box(Vector3(0.15, 0.022, 0.05), Color("b5975f"),
					Vector3(0, 0.06, -0.08 - float(turn) * 0.055))
				blade.rotation_degrees = Vector3(0, 0, float(turn) * 55.0)
				root.add_child(blade)
			root.add_child(_cyl(0.0, 0.055, 0.12, Color("d8c489"), Vector3(0, 0.06, -0.42), Vector3(90, 0, 0)))
			root.add_child(_box(Vector3(0.06, 0.15, 0.07), Color("35363c"), Vector3(0, -0.06, 0.1)))
			root.add_child(_box(Vector3(0.05, 0.04, 0.04), Color("ffd166"), Vector3(0, 0.15, -0.02), true))
		16:  # X-Ray Goggles: teal visor
			root.add_child(_box(Vector3(0.34, 0.12, 0.08), Color("7de8e0"), Vector3(0, 0.04, 0)))
			root.add_child(_box(Vector3(0.38, 0.03, 0.03), Color("35363c"), Vector3(0, 0.12, 0)))
		15:  # Big Shooter: genuinely double-barreled, ringed muzzles, grip
			for bs_side in [-1.0, 1.0]:
				root.add_child(_cyl(0.085, 0.085, 0.52, Color("d63d2e"),
					Vector3(bs_side * 0.09, 0.04, -0.02), Vector3(90, 0, 0)))
				root.add_child(_cyl(0.105, 0.105, 0.1, Color("8a2a20"),
					Vector3(bs_side * 0.09, 0.04, -0.26), Vector3(90, 0, 0)))
			root.add_child(_box(Vector3(0.26, 0.1, 0.16), Color("5c1d16"), Vector3(0, 0.04, 0.16)))
			root.add_child(_box(Vector3(0.1, 0.18, 0.12), Color("35363c"), Vector3(0, -0.1, 0.16)))
			root.add_child(_box(Vector3(0.05, 0.05, 0.05), Color("ffd166"), Vector3(0, 0.13, 0.1), true))
		14:  # Flare gun: stubby wide-mouth pistol
			root.add_child(_box(Vector3(0.1, 0.14, 0.1), Color("c94f4f"), Vector3(0, -0.04, 0.1)))
			root.add_child(_cyl(0.09, 0.11, 0.2, Color("ff8ac2"), Vector3(0, 0.05, -0.06), Vector3(90, 0, 0)))
		13:  # Sword: tapered blade with a fuller, a swept crossguard and a
			# wrapped grip. The old one was three flat slabs stacked up.
			root.add_child(_cyl(0.032, 0.038, 0.22, Color("4a3524"), Vector3(0, 0, 0.12), Vector3(90, 0, 0)))
			for wrap in [0.04, 0.10, 0.16]:
				root.add_child(_cyl(0.042, 0.042, 0.022, Color("2f2318"),
					Vector3(0, 0, 0.04 + wrap), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.055, 0.045, 0.06, Color("d9a832"), Vector3(0, 0, 0.25), Vector3(90, 0, 0)))
			# Crossguard, swept forward at the tips.
			root.add_child(_box(Vector3(0.1, 0.05, 0.055), Color("d9a832"), Vector3(0, 0, 0.0)))
			for guard_side in [-1.0, 1.0]:
				var quillon := _box(Vector3(0.1, 0.042, 0.05), Color("e8bd52"),
					Vector3(guard_side * 0.095, 0, -0.012))
				quillon.rotation_degrees = Vector3(0, guard_side * 16.0, 0)
				root.add_child(quillon)
			# Blade: wide at the ricasso, tapering to a point, with a
			# bright fuller down the middle catching the light.
			root.add_child(_box(Vector3(0.085, 0.028, 0.30), Color("dfe6f0"), Vector3(0, 0, -0.19)))
			root.add_child(_box(Vector3(0.068, 0.030, 0.26), Color("eef3fa"), Vector3(0, 0, -0.46)))
			root.add_child(_box(Vector3(0.026, 0.034, 0.52), Color("ffffff"), Vector3(0, 0, -0.32), true))
			# The point. The cone's ZERO radius has to be the end furthest
			# from the grip — built the other way round it reads as a
			# funnel stuck on the end of the blade, which is exactly what
			# it looked like.
			root.add_child(_cyl(0.034, 0.0, 0.13, Color("f7fafd"),
				Vector3(0, 0, -0.65), Vector3(90, 0, 0)))
		18:  # Paint sprayer: a pressure canister with a gauge, a hose and
			# a proper trigger handle.
			root.add_child(_cyl(0.085, 0.085, 0.3, Color("60d394"), Vector3(0, 0.08, 0.02), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.088, 0.088, 0.03, Color("3f9c6c"), Vector3(0, 0.08, -0.09), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.088, 0.088, 0.03, Color("3f9c6c"), Vector3(0, 0.08, 0.11), Vector3(90, 0, 0)))
			# Gauge on the shoulder.
			root.add_child(_cyl(0.032, 0.032, 0.03, Color("dfe6f0"), Vector3(0.05, 0.16, 0.06)))
			# Barrel and flared nozzle.
			root.add_child(_cyl(0.022, 0.022, 0.2, Color("cfd6e2"), Vector3(0, 0.09, -0.24), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.05, 0.022, 0.06, Color("9aa3b2"), Vector3(0, 0.09, -0.36), Vector3(90, 0, 0)))
			# Grip and trigger.
			root.add_child(_box(Vector3(0.055, 0.13, 0.07), Color("35363c"), Vector3(0, -0.02, 0.06)))
			root.add_child(_box(Vector3(0.02, 0.05, 0.02), Color("6c6f78"), Vector3(0, 0.03, 0.0)))
		19:  # Smoke bomb: a ribbed canister with a lever, a pin ring and
			# vent holes — something you can see is about to be thrown.
			root.add_child(_cyl(0.062, 0.062, 0.26, Color("9aa6c4"), Vector3(0, 0.09, -0.02), Vector3(90, 0, 0)))
			for band in [-0.09, 0.0, 0.09]:
				root.add_child(_cyl(0.068, 0.068, 0.022, Color("6f7a94"),
					Vector3(0, 0.09, band), Vector3(90, 0, 0)))
			# Vents at the business end.
			root.add_child(_cyl(0.05, 0.05, 0.04, Color("454c60"), Vector3(0, 0.09, -0.16), Vector3(90, 0, 0)))
			for vent in [-1.0, 1.0]:
				root.add_child(_cyl(0.012, 0.012, 0.03, Color("2a2f3c"),
					Vector3(vent * 0.025, 0.09, -0.18), Vector3(90, 0, 0)))
			# Spoon lever down the side, and the pin ring.
			root.add_child(_box(Vector3(0.022, 0.02, 0.19), Color("dfe6f0"), Vector3(0.058, 0.11, 0.0)))
			root.add_child(_cyl(0.034, 0.034, 0.012, Color("d9a832"), Vector3(0.075, 0.13, 0.1), Vector3(0, 90, 0)))
		11:  # Wings: a folded glider — a spar across your back with three
			# swept feathers each side, not two flat paddles.
			root.add_child(_cyl(0.022, 0.022, 0.36, Color("9aa3b2"), Vector3(0, 0.12, 0.02), Vector3(0, 0, 90)))
			for wing_side in [-1.0, 1.0]:
				for feather in range(3):
					var span := 0.30 - float(feather) * 0.06
					var quill := _box(Vector3(span, 0.016, 0.075 + float(feather) * 0.02),
						Color("eceff4").darkened(float(feather) * 0.08),
						Vector3(wing_side * (0.10 + span * 0.42), 0.12 - float(feather) * 0.012,
							-0.02 + float(feather) * 0.055))
					quill.rotation_degrees = Vector3(0, wing_side * (12.0 + float(feather) * 9.0),
						wing_side * (16.0 - float(feather) * 4.0))
					root.add_child(quill)
				root.add_child(_box(Vector3(0.05, 0.05, 0.05), Color("cfd6e2"),
					Vector3(wing_side * 0.09, 0.12, 0.02)))
		_:
			root.add_child(_box(Vector3(0.14, 0.14, 0.14), Weapons.spec(id).color, Vector3(0, 0.08, 0), true))
	return root
