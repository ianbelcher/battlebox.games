class_name BlockIcon
extends Control
## Hand-drawn item icons, no textures: blocks are shaded iso cubes, plants
## draw as flowers, the special machine blocks get symbol overlays, and every
## weapon is a bold colored roundel with its initial.

var block_id := 0
var kind := "block"   # block / weapon / structure / vehicle
var dimmed := false
var badge := ""

func _init(p_block := 0, p_kind := "block") -> void:
	block_id = p_block
	kind = p_kind
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _dim(c: Color) -> Color:
	return c.darkened(0.3) if dimmed else c

static var _weapon_textures: Dictionary = {}

static func _weapon_texture(id: int) -> Texture2D:
	if _weapon_textures.has(id):
		return _weapon_textures[id]
	var tex: Texture2D = null
	var path := "res://assets/ui/weapons/w%d.png" % id
	if ResourceLoader.exists(path):
		tex = load(path)
	_weapon_textures[id] = tex
	return tex

func _draw() -> void:
	# Kit thumbnails are 16x16 — keep them pixel-crisp, never smeared.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if kind == "empty":
		draw_circle(size * 0.5, size.x * 0.06, Color(1, 1, 1, 0.2))
		return
	var w := size.x
	var h := size.y
	var mid := Vector2(w, h) * 0.5
	if kind == "weapon":
		_draw_weapon(w, h, mid)
	elif kind == "structure":
		_draw_structure(w, h)
	elif kind == "vehicle":
		_draw_vehicle(w, h)
	else:
		_draw_block(w, h, mid)

## A BOAT OR A CAR, in profile.
##
## There was no branch for this at all, so both fell through to
## `_draw_block` with the vehicle KIND as a block id — 0 and 1, which are
## air and stone. A car drew as a grey cube and a boat as nothing, which
## is why there was "no icon for car".
##
## Drawn rather than rendered: these are two shapes and a wheel, and a
## model would need a viewport per icon for something the size of a
## thumbnail.
func _draw_vehicle(w: float, h: float) -> void:
	var boat: bool = block_id == VehicleGeom.KIND_BOAT
	var body: Color = Color("8a5a34") if boat else Color("c8503c")
	var trim: Color = Color("d8c39a") if boat else Color("2f3542")
	draw_rect(Rect2(w * 0.06, h * 0.30, w * 0.88, h * 0.40),
		Color(body.r, body.g, body.b, 0.16))
	if boat:
		# A hull: flat deck, sloped bow and stern, and a mast.
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.12, h * 0.56), Vector2(w * 0.88, h * 0.56),
			Vector2(w * 0.74, h * 0.76), Vector2(w * 0.26, h * 0.76)]), body)
		draw_rect(Rect2(w * 0.47, h * 0.22, w * 0.06, h * 0.34), trim)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.53, h * 0.24), Vector2(w * 0.78, h * 0.40),
			Vector2(w * 0.53, h * 0.50)]), trim)
	else:
		# A car: body, cab, two wheels.
		draw_rect(Rect2(w * 0.12, h * 0.50, w * 0.76, h * 0.20), body)
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.30, h * 0.50), Vector2(w * 0.42, h * 0.32),
			Vector2(w * 0.66, h * 0.32), Vector2(w * 0.74, h * 0.50)]), trim)
		draw_circle(Vector2(w * 0.29, h * 0.72), w * 0.09, Color("1b1f2a"))
		draw_circle(Vector2(w * 0.71, h * 0.72), w * 0.09, Color("1b1f2a"))
		draw_circle(Vector2(w * 0.29, h * 0.72), w * 0.04, Color("6b7280"))
		draw_circle(Vector2(w * 0.71, h * 0.72), w * 0.04, Color("6b7280"))

## A weapon: a soft tinted plate with the actual weapon drawn in profile
## on top of it, or its rendered model where one exists.
func _draw_weapon(w: float, h: float, mid: Vector2) -> void:
	var spec := Weapons.spec(block_id)
	var c := _dim(spec.color)
	# Soft tinted plate + the ACTUAL weapon rendered in profile. The
	# plate is ROUNDED to match the chip it sits inside — a square
	# plate in a rounded chip reads as a mistake at any size.
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(c.r, c.g, c.b, 0.16)
	plate.border_color = Color(c.r, c.g, c.b, 0.85)
	plate.set_border_width_all(maxi(1, int(w * 0.035)))
	plate.set_corner_radius_all(maxi(3, int(w * 0.14)))
	plate.corner_detail = 8
	draw_style_box(plate, Rect2(w * 0.05, h * 0.05, w * 0.9, h * 0.9))
	var wtex := _weapon_texture(block_id)
	if wtex != null:
		draw_texture_rect(wtex, Rect2(w * 0.08, h * 0.08, w * 0.84, h * 0.84),
			false, Color(0.62, 0.62, 0.62) if dimmed else Color.WHITE)
		return
	var ink := Color(c.lightened(0.22), 1.0)
	draw_set_transform(mid * -0.4, 0.0, Vector2(1.4, 1.4))
	match block_id:
		13:  # Sword: diagonal blade, crossguard, pommel.
			draw_line(mid + Vector2(-w * 0.1, w * 0.14), mid + Vector2(w * 0.16, -w * 0.12), ink, w * 0.07)
			draw_colored_polygon(PackedVector2Array([mid + Vector2(w * 0.13, -w * 0.16),
				mid + Vector2(w * 0.24, -w * 0.2), mid + Vector2(w * 0.2, -w * 0.09)]), ink)
			draw_line(mid + Vector2(-w * 0.16, w * 0.02), mid + Vector2(-w * 0.02, w * 0.2), ink, w * 0.05)
			draw_circle(mid + Vector2(-w * 0.16, w * 0.2), w * 0.045, ink)
		0:  # Blaster: three speed pellets.
			for i in 3:
				draw_circle(mid + Vector2((i - 1) * w * 0.16, (i - 1) * -w * 0.05), w * 0.07, ink)
		1:  # Bazooka: rocket.
			draw_rect(Rect2(mid.x - w * 0.2, mid.y - w * 0.08, w * 0.28, w * 0.16), ink)
			draw_colored_polygon(PackedVector2Array([mid + Vector2(w * 0.08, -w * 0.14),
				mid + Vector2(w * 0.26, 0), mid + Vector2(w * 0.08, w * 0.14)]), ink)
		2:  # Grapple: hook.
			draw_arc(mid + Vector2(0, w * 0.04), w * 0.16, PI * 0.1, PI * 1.4, 12, ink, w * 0.06)
			draw_line(mid + Vector2(w * 0.12, -w * 0.1), mid + Vector2(w * 0.22, -w * 0.22), ink, w * 0.06)
		3:  # Freeze: snowflake.
			for i in 3:
				var a := i * PI / 3.0
				draw_line(mid - Vector2(cos(a), sin(a)) * w * 0.2,
					mid + Vector2(cos(a), sin(a)) * w * 0.2, ink, w * 0.05)
		4:  # Sucker: inward arrows.
			for i in 4:
				var a := i * TAU / 4.0 + TAU / 8.0
				var dir := Vector2(cos(a), sin(a))
				draw_line(mid + dir * w * 0.24, mid + dir * w * 0.08, ink, w * 0.055)
		18:  # Paint sprayer: a can with a spray fan in team colours.
			draw_rect(Rect2(mid.x - w * 0.13, mid.y - w * 0.12, w * 0.2, w * 0.34), ink)
			draw_rect(Rect2(mid.x - w * 0.07, mid.y - w * 0.2, w * 0.08, w * 0.09), ink)
			for i in 5:
				var spray := mid + Vector2(w * 0.14 + w * 0.05 * i,
					-w * 0.2 + w * 0.055 * i)
				draw_circle(spray, w * 0.035, ink)
		19:  # Smoke bomb: a canister under one solid BANK of smoke.
			# Drawn as a cloud, not as rising dots: as three separate
			# puffs it read as three circles, which is exactly what the
			# paint bomb below is, and at hotbar size the two were the
			# same picture.
			draw_rect(Rect2(mid.x - w * 0.09, mid.y + w * 0.08, w * 0.18, w * 0.2), ink)
			var puff := Color(0.86, 0.89, 0.95, 0.92)
			for puff_spec: Array in [[-0.17, -0.02, 0.13], [0.0, -0.09, 0.17],
					[0.17, -0.02, 0.13], [-0.08, 0.03, 0.11], [0.08, 0.03, 0.11]]:
				draw_circle(mid + Vector2(w * float(puff_spec[0]), w * float(puff_spec[1])),
					w * float(puff_spec[2]), puff)
		8:  # Paint: drips.
			draw_circle(mid + Vector2(-w * 0.1, -w * 0.05), w * 0.09, Color("d63d2e"))
			draw_circle(mid + Vector2(w * 0.1, -w * 0.02), w * 0.08, Color(0.15, 0.3, 0.75))
			draw_circle(mid + Vector2(0, w * 0.14), w * 0.07, Color(0.15, 0.55, 0.25))
		9:  # Napalm: flame.
			draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -w * 0.22),
				mid + Vector2(w * 0.14, w * 0.1), mid + Vector2(0, w * 0.2),
				mid + Vector2(-w * 0.14, w * 0.1)]), Color("d63d2e"))
			draw_circle(mid + Vector2(0, w * 0.06), w * 0.08, Color("ffd166"))
		10:  # Grump whistle: angry eyes.
			for side in [-1.0, 1.0]:
				draw_circle(mid + Vector2(side * w * 0.1, -w * 0.03), w * 0.07, ink)
				draw_line(mid + Vector2(side * w * 0.04, -w * 0.16),
					mid + Vector2(side * w * 0.18, -w * 0.1), ink, w * 0.045)
		11:  # Wings.
			for side in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([mid,
					mid + Vector2(side * w * 0.26, -w * 0.14),
					mid + Vector2(side * w * 0.18, w * 0.1)]), ink)
		12:  # Digger: shovel.
			draw_line(mid + Vector2(-w * 0.12, -w * 0.18), mid + Vector2(w * 0.04, w * 0.02), ink, w * 0.055)
			draw_colored_polygon(PackedVector2Array([mid + Vector2(w * 0.0, -w * 0.02),
				mid + Vector2(w * 0.2, w * 0.08), mid + Vector2(w * 0.06, w * 0.2)]), ink)
		16:  # X-Ray: goggles.
			for side in [-1.0, 1.0]:
				draw_circle(mid + Vector2(side * w * 0.11, 0), w * 0.1, ink, false, w * 0.045)
			draw_line(mid + Vector2(-w * 0.02, 0), mid + Vector2(w * 0.02, 0), ink, w * 0.04)
		15:  # Big Shooter: fat rocket.
			draw_rect(Rect2(mid.x - w * 0.24, mid.y - w * 0.12, w * 0.34, w * 0.24), ink)
			draw_colored_polygon(PackedVector2Array([mid + Vector2(w * 0.1, -w * 0.2),
				mid + Vector2(w * 0.32, 0), mid + Vector2(w * 0.1, w * 0.2)]), ink)
		14:  # Flare gun: rising star.
			draw_line(mid + Vector2(0, w * 0.2), mid + Vector2(0, -w * 0.08), ink, w * 0.06)
			for star_i in 4:
				var sa := star_i * TAU / 4.0 + 0.4
				draw_line(mid + Vector2(0, -w * 0.14),
					mid + Vector2(0, -w * 0.14) + Vector2(cos(sa), sin(sa)) * w * 0.12, ink, w * 0.04)
		_:
			draw_circle(mid, w * 0.1, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return

## A building kit: a tiny elevation of the thing it stamps.
func _draw_structure(w: float, h: float) -> void:
	var c := _dim(Structures.spec(block_id).color)
	var dark := c.darkened(0.3)
	match block_id:
		12:  # Treehouse: canopy + platform + trunk.
			draw_rect(Rect2(w * 0.44, h * 0.5, w * 0.12, h * 0.4), Color("6b4a2f"))
			draw_rect(Rect2(w * 0.2, h * 0.42, w * 0.6, h * 0.1), Color("b08d5e"))
			draw_circle(Vector2(w * 0.5, h * 0.28), w * 0.26, c)
		13:  # Windmill: tower + cross sails.
			draw_rect(Rect2(w * 0.4, h * 0.3, w * 0.2, h * 0.6), dark)
			for a_i in 4:
				var ang := a_i * TAU / 4.0 + TAU / 8.0
				draw_line(Vector2(w * 0.5, h * 0.3),
					Vector2(w * 0.5, h * 0.3) + Vector2(cos(ang), sin(ang)) * w * 0.26,
					Color("f0ead8"), w * 0.07)
		14:  # Castle gate: twin towers + arch.
			draw_rect(Rect2(w * 0.1, h * 0.2, w * 0.2, h * 0.7), c)
			draw_rect(Rect2(w * 0.7, h * 0.2, w * 0.2, h * 0.7), c)
			draw_rect(Rect2(w * 0.3, h * 0.44, w * 0.4, h * 0.14), dark)
			draw_rect(Rect2(w * 0.38, h * 0.58, w * 0.24, h * 0.32), Color(0.08, 0.08, 0.12, 0.85))
		0:  # Little House
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.08),
				Vector2(w * 0.92, h * 0.45), Vector2(w * 0.08, h * 0.45)]), c)
			draw_rect(Rect2(w * 0.18, h * 0.45, w * 0.64, h * 0.45), dark)
			draw_rect(Rect2(w * 0.42, h * 0.62, w * 0.16, h * 0.28), Color(0.08, 0.08, 0.12, 0.85))
		1:  # Watchtower
			draw_rect(Rect2(w * 0.34, h * 0.2, w * 0.32, h * 0.7), c)
			for i in 3:
				draw_rect(Rect2(w * (0.3 + i * 0.15), h * 0.1, w * 0.1, h * 0.12), c)
			draw_rect(Rect2(w * 0.42, h * 0.72, w * 0.16, h * 0.18), Color(0.08, 0.08, 0.12, 0.85))
		2:  # Giant Tree
			draw_rect(Rect2(w * 0.42, h * 0.5, w * 0.16, h * 0.4), Color("6b4a2f"))
			draw_circle(Vector2(w * 0.5, h * 0.34), w * 0.3, c)
		3:  # Bridge
			draw_rect(Rect2(w * 0.08, h * 0.42, w * 0.84, h * 0.12), c)
			draw_rect(Rect2(w * 0.14, h * 0.54, w * 0.1, h * 0.34), dark)
			draw_rect(Rect2(w * 0.76, h * 0.54, w * 0.1, h * 0.34), dark)
		4:  # Campsite
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.38, h * 0.2),
				Vector2(w * 0.66, h * 0.62), Vector2(w * 0.1, h * 0.62)]), c)
			draw_circle(Vector2(w * 0.76, h * 0.68), w * 0.09, Color("ff6a3d"))
		5:  # Fort Wall
			draw_rect(Rect2(w * 0.08, h * 0.4, w * 0.84, h * 0.42), c)
			for i in 4:
				draw_rect(Rect2(w * (0.1 + i * 0.22), h * 0.28, w * 0.12, h * 0.14), c)
		6:  # Pool
			draw_rect(Rect2(w * 0.12, h * 0.3, w * 0.76, h * 0.44), dark)
			draw_rect(Rect2(w * 0.18, h * 0.36, w * 0.64, h * 0.32), Color("62b8f5"))
		7:  # Flower Garden
			draw_rect(Rect2(w * 0.1, h * 0.62, w * 0.8, h * 0.2), Color("58a850"))
			for i in 3:
				draw_circle(Vector2(w * (0.26 + i * 0.24), h * 0.44), w * 0.08,
					[Color("ff6b6b"), Color("ffd166"), Color("ff9ff3")][i])
		8:  # Fort
			draw_rect(Rect2(w * 0.1, h * 0.26, w * 0.2, h * 0.6), c)
			draw_rect(Rect2(w * 0.7, h * 0.26, w * 0.2, h * 0.6), c)
			draw_rect(Rect2(w * 0.24, h * 0.5, w * 0.52, h * 0.36), dark)
		9:  # Steel Bunker
			draw_circle(Vector2(w * 0.5, h * 0.72), w * 0.34, c)
			draw_rect(Rect2(w * 0.16, h * 0.72, w * 0.68, h * 0.18), c)
			draw_rect(Rect2(w * 0.36, h * 0.58, w * 0.28, h * 0.07), Color(0.08, 0.08, 0.12, 0.85))
		10:  # Sniper Tower
			draw_rect(Rect2(w * 0.3, h * 0.14, w * 0.4, h * 0.26), c)
			draw_line(Vector2(w * 0.36, h * 0.4), Vector2(w * 0.36, h * 0.88), dark, w * 0.05)
			draw_line(Vector2(w * 0.64, h * 0.4), Vector2(w * 0.64, h * 0.88), dark, w * 0.05)
		11:  # Barricade
			draw_line(Vector2(w * 0.14, h * 0.78), Vector2(w * 0.86, h * 0.3), c, w * 0.12)
			draw_line(Vector2(w * 0.14, h * 0.3), Vector2(w * 0.86, h * 0.78), c, w * 0.12)
		_:
			# Imported Minecraft builds draw a front elevation of the
			# ACTUAL build, baked at import — a library looks like a
			# library, not like every other kit.
			var shot := Structures.thumbnail(block_id)
			if shot != null:
				var side := minf(w, h) * 0.92
				var at := Vector2((w - side) * 0.5, (h - side) * 0.5)
				draw_texture_rect(shot, Rect2(at, Vector2(side, side)), false)
			else:
				var roof := _dim(Structures.spec(block_id).get("roof", c))
				draw_colored_polygon(PackedVector2Array([
					Vector2(w * 0.5, h * 0.12), Vector2(w * 0.9, h * 0.42),
					Vector2(w * 0.1, h * 0.42)]), roof)
				draw_rect(Rect2(w * 0.18, h * 0.42, w * 0.64, h * 0.46), c)
	return

## A block. Some have a glyph of their own (a torch, a vine, a ladder);
## the rest fall through to an isometric cube in the block's colours.
func _draw_block(w: float, h: float, mid: Vector2) -> void:
	# Blocks with their own recognizable glyphs (Minecraft-style).
	match block_id:
		Blocks.TORCH:
			draw_rect(Rect2(mid.x - w * 0.05, h * 0.34, w * 0.1, h * 0.5), _dim(Color("8a6242")))
			draw_circle(Vector2(mid.x, h * 0.28), w * 0.12, Color(1, 0.85, 0.4, 0.5))
			draw_circle(Vector2(mid.x, h * 0.28), w * 0.08, _dim(Color("ffd166")))
			return
		Blocks.VINE:
			var vine := _dim(Blocks.color_of(block_id))
			for i in 3:
				var vx := w * (0.28 + i * 0.22)
				draw_line(Vector2(vx, h * 0.1), Vector2(vx, h * (0.62 + (i % 2) * 0.24)), vine, w * 0.07)
				draw_circle(Vector2(vx + w * 0.05, h * (0.3 + i * 0.16)), w * 0.06, vine.lightened(0.2))
			return
		Blocks.LADDER:
			var rail := _dim(Color("9a7a4f"))
			for lx in [0.3, 0.7]:
				draw_rect(Rect2(w * lx - w * 0.045, h * 0.1, w * 0.09, h * 0.8), rail)
			for i in 4:
				draw_rect(Rect2(w * 0.26, h * (0.18 + i * 0.2), w * 0.48, h * 0.07), rail.lightened(0.15))
			return
		Blocks.BAMBOO:
			var stalk := _dim(Blocks.color_of(block_id))
			draw_rect(Rect2(mid.x - w * 0.06, h * 0.08, w * 0.12, h * 0.84), stalk)
			for i in 3:
				draw_rect(Rect2(mid.x - w * 0.08, h * (0.24 + i * 0.24), w * 0.16, h * 0.035), stalk.darkened(0.3))
			draw_line(Vector2(mid.x, h * 0.2), Vector2(mid.x + w * 0.22, h * 0.1), stalk.lightened(0.2), w * 0.05)
			return
	match block_id:
		Blocks.DOOR_WOOD, Blocks.DOOR_IRON:
			var door_c := _dim(Blocks.color_of(block_id))
			draw_rect(Rect2(w * 0.26, h * 0.06, w * 0.48, h * 0.88), door_c)
			draw_rect(Rect2(w * 0.26, h * 0.06, w * 0.48, h * 0.88),
				door_c.darkened(0.35), false, w * 0.025)
			draw_rect(Rect2(w * 0.33, h * 0.14, w * 0.34, h * 0.3), door_c.darkened(0.2))
			draw_rect(Rect2(w * 0.33, h * 0.52, w * 0.34, h * 0.3), door_c.darkened(0.2))
			draw_circle(Vector2(w * 0.66, h * 0.5), w * 0.04, Color("ffd166"))
			return
		Blocks.BED:
			draw_rect(Rect2(w * 0.1, h * 0.5, w * 0.8, h * 0.24), _dim(Blocks.color_of(block_id)))
			draw_rect(Rect2(w * 0.1, h * 0.38, w * 0.26, h * 0.16), Color(0.95, 0.95, 0.97))
			draw_rect(Rect2(w * 0.08, h * 0.72, w * 0.06, h * 0.18), Color("6b4a2f"))
			draw_rect(Rect2(w * 0.86, h * 0.72, w * 0.06, h * 0.18), Color("6b4a2f"))
			return
		Blocks.LILY_PAD:
			draw_circle(Vector2(w * 0.5, h * 0.55), w * 0.3, _dim(Blocks.color_of(block_id)))
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.55),
				Vector2(w * 0.78, h * 0.42), Vector2(w * 0.72, h * 0.6)]),
				Color(0.16, 0.24, 0.4))
			return
	var icon_shape := Blocks.shape_of(block_id)
	if icon_shape != "" and icon_shape != "stairs":
		var c := _dim(Blocks.color_of(block_id))
		match icon_shape:
			"slab", "carpet":
				var top_y := h * (0.5 if icon_shape == "slab" else 0.68)
				draw_colored_polygon(PackedVector2Array([Vector2(mid.x, top_y - h * 0.2),
					Vector2(w * 0.94, top_y - h * 0.06), Vector2(mid.x, top_y + h * 0.08),
					Vector2(w * 0.06, top_y - h * 0.06)]), c.lightened(0.15))
				draw_colored_polygon(PackedVector2Array([Vector2(w * 0.06, top_y - h * 0.06),
					Vector2(mid.x, top_y + h * 0.08), Vector2(mid.x, h * 0.92),
					Vector2(w * 0.06, h * 0.78)]), c.darkened(0.25))
				draw_colored_polygon(PackedVector2Array([Vector2(mid.x, top_y + h * 0.08),
					Vector2(w * 0.94, top_y - h * 0.06), Vector2(w * 0.94, h * 0.78),
					Vector2(mid.x, h * 0.92)]), c.darkened(0.42))
			"fence":
				draw_rect(Rect2(w * 0.24, h * 0.15, w * 0.1, h * 0.72), c)
				draw_rect(Rect2(w * 0.66, h * 0.15, w * 0.1, h * 0.72), c)
				for ry in [0.32, 0.6]:
					draw_rect(Rect2(w * 0.1, h * ry, w * 0.8, h * 0.09), c.lightened(0.12))
			"wall":
				draw_rect(Rect2(w * 0.34, h * 0.12, w * 0.32, h * 0.78), c)
				draw_rect(Rect2(w * 0.1, h * 0.38, w * 0.8, h * 0.42), c.darkened(0.15))
			"pane":
				draw_rect(Rect2(w * 0.3, h * 0.08, w * 0.4, h * 0.84),
					Color(c.r, c.g, c.b, 0.55))
				draw_rect(Rect2(w * 0.3, h * 0.08, w * 0.4, h * 0.84),
					Color(1, 1, 1, 0.5), false, w * 0.03)
				draw_line(Vector2(w * 0.38, h * 0.7), Vector2(w * 0.56, h * 0.24),
					Color(1, 1, 1, 0.6), w * 0.04)
		return
	if icon_shape == "stairs":
		var c := _dim(Blocks.color_of(block_id))
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.1, h * 0.88), Vector2(w * 0.1, h * 0.52),
			Vector2(mid.x, h * 0.52), Vector2(mid.x, h * 0.16),
			Vector2(w * 0.9, h * 0.16), Vector2(w * 0.9, h * 0.88)]), c)
		draw_line(Vector2(w * 0.1, h * 0.52), Vector2(mid.x, h * 0.52), c.lightened(0.3), w * 0.03)
		draw_line(Vector2(mid.x, h * 0.16), Vector2(w * 0.9, h * 0.16), c.lightened(0.3), w * 0.03)
		return
	if Blocks.is_cross(block_id):
		_draw_plant_icon(w, h)
		return
	_draw_iso_cube(w, h)
	return

## The iso cube corners, shared by the base fill and the face patterns.
## Faces: 0 = top diamond, 1 = left, 2 = right. (u,v) in [0,1] maps
## across each face so patterns can be drawn in flat face-space.
func _face_pt(face: int, u: float, v: float) -> Vector2:
	# Flat, Minecraft-texture-style icons: one full square face. "Top"
	# pattern elements land on the upper strip; side elements cover the
	# whole tile.
	var w := size.x
	var h := size.y
	if face == 0:
		return Vector2(w * (0.07 + u * 0.86), h * (0.07 + v * 0.26))
	return Vector2(w * (0.07 + u * 0.86), h * (0.07 + v * 0.86))

func _face_quad(face: int, u0: float, v0: float, u1: float, v1: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([_face_pt(face, u0, v0),
		_face_pt(face, u1, v0), _face_pt(face, u1, v1), _face_pt(face, u0, v1)]), color)

func _face_line(face: int, u0: float, v0: float, u1: float, v1: float, color: Color, width: float) -> void:
	draw_line(_face_pt(face, u0, v0), _face_pt(face, u1, v1), color, width)

func _hashf(n: float) -> float:
	return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)

func _draw_iso_cube(w: float, h: float) -> void:
	var mid := Vector2(w, h) * 0.5
	var top := _dim(Blocks.top_color_of(block_id))
	var side := _dim(Blocks.color_of(block_id))
	# Flat tile, like a Minecraft texture square: the block's face IS the
	# icon. Blocks with a distinct top get a strip of it along the top
	# edge (the grass-block look); everything else is one clean face.
	draw_rect(Rect2(w * 0.05, h * 0.05, w * 0.9, h * 0.9),
		Color(side.r, side.g, side.b))
	if top != side:
		draw_rect(Rect2(w * 0.05, h * 0.05, w * 0.9, h * 0.28),
			Color(top.r, top.g, top.b))
	# A soft edge so tiles read as tiles on any background.
	draw_rect(Rect2(w * 0.05, h * 0.05, w * 0.9, h * 0.9),
		Color(0, 0, 0, 0.35), false, w * 0.028)
	_draw_cube_pattern(side, top)
	# Symbol overlays so the machine blocks read at a glance.
	var overlay := Color(1, 1, 1, 0.9)
	match block_id:
		Blocks.BOOM:
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(mid, mid + Vector2(cos(a), sin(a)) * w * 0.28, overlay, w * 0.045)
		Blocks.LAUNCHER:
			draw_colored_polygon(PackedVector2Array([Vector2(mid.x, h * 0.22),
				Vector2(w * 0.72, h * 0.55), Vector2(w * 0.28, h * 0.55)]), overlay)
		Blocks.TELEPORT:
			draw_circle(mid, w * 0.24, overlay, false, w * 0.06)
		Blocks.NOTE:
			draw_rect(Rect2(w * 0.36, h * 0.24, w * 0.07, h * 0.4), overlay)
			draw_circle(Vector2(w * 0.34, h * 0.64), w * 0.09, overlay)
			draw_rect(Rect2(w * 0.43, h * 0.24, w * 0.18, h * 0.08), overlay)
		Blocks.BOUNCY:
			for i in 3:
				draw_line(Vector2(w * 0.28, h * (0.35 + i * 0.14)),
					Vector2(w * 0.72, h * (0.35 + i * 0.14)), overlay, w * 0.05)
		Blocks.SPONGE:
			for pos in [Vector2(0.36, 0.4), Vector2(0.6, 0.34), Vector2(0.5, 0.58), Vector2(0.66, 0.55)]:
				draw_circle(Vector2(w * pos.x, h * pos.y), w * 0.06, Color(0.4, 0.35, 0.1, 0.8))
		Blocks.CONFETTI:
			for i in 6:
				var a := i * TAU / 6.0 + 0.4
				draw_circle(mid + Vector2(cos(a), sin(a)) * w * 0.22, w * 0.06,
					[Color("ff6b6b"), Color("ffd166"), Color("4a9df8")][i % 3])
		Blocks.LANTERN, Blocks.GLOWSTONE:
			for i in 6:
				var a := i * TAU / 6.0
				draw_line(mid + Vector2(cos(a), sin(a)) * w * 0.14,
					mid + Vector2(cos(a), sin(a)) * w * 0.26, Color(1, 1, 0.8, 0.9), w * 0.04)
			draw_circle(mid, w * 0.1, Color(1, 0.95, 0.7))
		Blocks.CAMPFIRE, Blocks.LAVA:
			draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -w * 0.2),
				mid + Vector2(w * 0.12, w * 0.08), mid + Vector2(0, w * 0.16),
				mid + Vector2(-w * 0.12, w * 0.08)]), Color(1, 0.5, 0.15, 0.95))
		Blocks.FIREWORK:
			draw_line(Vector2(w * 0.35, h * 0.65), Vector2(w * 0.62, h * 0.3), overlay, w * 0.05)
			for i in 5:
				var a := i * TAU / 5.0
				draw_line(Vector2(w * 0.62, h * 0.3),
					Vector2(w * 0.62, h * 0.3) + Vector2(cos(a), sin(a)) * w * 0.12, overlay, w * 0.03)
		_:
			if Blocks.is_translucent(block_id):
				draw_line(mid + Vector2(-w * 0.16, w * 0.12), mid + Vector2(w * 0.04, -w * 0.16), Color(1, 1, 1, 0.8), w * 0.05)
				draw_line(mid + Vector2(-w * 0.02, w * 0.16), mid + Vector2(w * 0.14, -w * 0.06), Color(1, 1, 1, 0.6), w * 0.04)

## Plant icons mirror the in-world silhouettes so kids recognize them.
func _draw_plant_icon(w: float, h: float) -> void:
	var c := _dim(Blocks.color_of(block_id))
	var green := _dim(Color("4a7a35"))
	match block_id:
		Blocks.TALL_GRASS, Blocks.FERN:
			for i in 5:
				var root := w * (0.2 + 0.15 * i)
				var tip_x := root + (root - w * 0.5) * 0.5
				var tall := h * (0.35 + 0.35 * _hashf(float(i)))
				draw_line(Vector2(root, h * 0.92), Vector2(tip_x, h * 0.92 - tall),
					c, w * (0.05 - 0.006 * i))
		Blocks.MUSHROOM:
			draw_rect(Rect2(w * 0.42, h * 0.5, w * 0.16, h * 0.4), _dim(Color("e8dcc2")))
			draw_circle(Vector2(w * 0.5, h * 0.5), w * 0.3, c)
			draw_rect(Rect2(w * 0.2, h * 0.5, w * 0.6, h * 0.06), c)
			for dot in [Vector2(0.4, 0.34), Vector2(0.6, 0.4)]:
				draw_circle(Vector2(w * dot.x, h * dot.y), w * 0.05, Color(1, 1, 1, 0.85))
		Blocks.FIRE:
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.08),
				Vector2(w * 0.72, h * 0.5), Vector2(w * 0.62, h * 0.9),
				Vector2(w * 0.38, h * 0.9), Vector2(w * 0.28, h * 0.5)]), _dim(Color("f0632a")))
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.38),
				Vector2(w * 0.6, h * 0.66), Vector2(w * 0.5, h * 0.88),
				Vector2(w * 0.4, h * 0.66)]), _dim(Color("ffd166")))
		Blocks.SAPLING, Blocks.BERRY_BUSH, Blocks.DEAD_BUSH:
			draw_rect(Rect2(w * 0.46, h * 0.6, w * 0.08, h * 0.3), _dim(Color("6b4a2f")))
			for lobe in [Vector2(0.36, 0.42), Vector2(0.64, 0.46), Vector2(0.5, 0.28)]:
				draw_circle(Vector2(w * lobe.x, h * lobe.y), w * 0.19, c)
			if block_id == Blocks.BERRY_BUSH:
				for berry in [Vector2(0.4, 0.4), Vector2(0.6, 0.5), Vector2(0.52, 0.32)]:
					draw_circle(Vector2(w * berry.x, h * berry.y), w * 0.045, _dim(Color("d63d4a")))
		Blocks.WHEAT_PLANT, Blocks.CATTAIL:
			for i in 4:
				var root := w * (0.24 + 0.17 * i)
				var tall := h * (0.5 + 0.3 * _hashf(float(i + 2)))
				draw_line(Vector2(root, h * 0.92), Vector2(root, h * 0.92 - tall), c, w * 0.03)
				draw_rect(Rect2(root - w * 0.035, h * 0.92 - tall - h * 0.1,
					w * 0.07, h * 0.12), c.lightened(0.15))
		_:
			# Flower: green stem, leaf, scalloped petal head + warm center.
			draw_line(Vector2(w * 0.5, h * 0.9), Vector2(w * 0.5, h * 0.42), green, w * 0.045)
			draw_circle(Vector2(w * 0.4, h * 0.68), w * 0.06, green)
			for petal_i in 6:
				var pa := petal_i * TAU / 6.0
				draw_circle(Vector2(w * 0.5, h * 0.3) + Vector2(cos(pa), sin(pa)) * w * 0.13,
					w * 0.1, c)
			draw_circle(Vector2(w * 0.5, h * 0.3), w * 0.09, _dim(Color("ffd166")))

## Minecraft-style face texturing so every cube reads as its material,
## not just a colored box (kids can't read the names).
func _draw_cube_pattern(side: Color, top: Color) -> void:
	var w := size.x
	var h := size.y
	var mid := Vector2(w, h) * 0.5
	var b := block_id
	var dark := Color(0, 0, 0, 0.28)
	var faint := Color(0, 0, 0, 0.16)
	var lite := Color(1, 1, 1, 0.22)
	if b == Blocks.GRASS or b == 122 or b == 123:
		# The icon of icons: dirt sides with a grass fringe dripping down.
		for face in [1]:
			_face_quad(face, 0.0, 0.0, 1.0, 0.18, Color(top.r * 0.9, top.g * 0.9, top.b * 0.9))
			for i in 4:
				_face_quad(face, 0.08 + 0.24 * i, 0.14, 0.2 + 0.24 * i,
					0.3 + 0.1 * _hashf(float(i + face)), Color(top.r * 0.85, top.g * 0.85, top.b * 0.85))
	elif b == Blocks.LOG or b in [125, 126, 127, 128, 130, Blocks.WARPED_STEM,
			Blocks.BAMBOO_BLOCK]:
		for ring in [0.32, 0.6]:
			draw_arc(_face_pt(0, 0.5, 0.5), size.x * 0.5 * ring * 0.42, 0, TAU, 16, dark, size.x * 0.02)
		for face in [1]:
			for i in 3:
				_face_line(face, 0.2 + 0.3 * i, 0.05, 0.2 + 0.3 * i, 0.95, dark, size.x * 0.025)
	elif b == Blocks.PLANKS or b in [Blocks.BIRCH_PLANKS, Blocks.DARK_PLANKS,
			Blocks.CHERRY_PLANKS, 129, 131, Blocks.WARPED_PLANKS,
			Blocks.CRIMSON_PLANKS, Blocks.MANGROVE_PLANKS]:
		for face in [1]:
			for i in 3:
				_face_line(face, 0.0, 0.25 * (i + 1), 1.0, 0.25 * (i + 1), dark, size.x * 0.02)
			_face_line(face, 0.5, 0.0, 0.5, 0.25, faint, size.x * 0.02)
			_face_line(face, 0.25, 0.5, 0.25, 0.75, faint, size.x * 0.02)
		_face_line(0, 0.0, 0.33, 1.0, 0.33, dark, size.x * 0.02)
		_face_line(0, 0.0, 0.66, 1.0, 0.66, dark, size.x * 0.02)
	elif b == Blocks.BRICK or b in [101, 102, 103, 109, 115, 119]:
		for face in [1]:
			for row in 3:
				_face_line(face, 0.0, 0.33 * (row + 1), 1.0, 0.33 * (row + 1), dark, size.x * 0.02)
				var off := 0.25 if row % 2 == 0 else 0.5
				_face_line(face, off, 0.33 * row, off, 0.33 * (row + 1), dark, size.x * 0.02)
				_face_line(face, minf(off + 0.5, 0.95), 0.33 * row, minf(off + 0.5, 0.95),
					0.33 * (row + 1), dark, size.x * 0.02)
	elif b == Blocks.COBBLE or b == Blocks.MOSSY_COBBLE or b == 121:
		for face in [1]:
			for i in 4:
				var cu := 0.2 + 0.5 * _hashf(float(i * 3 + face))
				var cv := 0.2 + 0.55 * _hashf(float(i * 7 + face + 1))
				draw_arc(_face_pt(face, cu, cv), size.x * (0.05 + 0.03 * _hashf(float(i))),
					0, TAU, 8, dark, size.x * 0.018)
	elif b == Blocks.LEAVES or b in [Blocks.LEAVES_DARK, Blocks.LEAVES_LIGHT,
			Blocks.LEAVES_PINK, 133]:
		# Mottled leaf clumps, lighter and darker — clearly a bush cube.
		for face in [1]:
			for i in 5:
				var lu := 0.12 + 0.75 * _hashf(float(i * 5 + face * 2))
				var lv := 0.12 + 0.75 * _hashf(float(i * 11 + face))
				var leaf_col := Color(side.lightened(0.22), 0.85) if i % 2 == 0 \
					else Color(side.darkened(0.28), 0.85)
				_face_quad(face, lu, lv, minf(lu + 0.2, 0.98), minf(lv + 0.2, 0.98), leaf_col)
	elif b >= Blocks.WOOL_RED and b <= Blocks.WOOL_BLACK or b in [Blocks.WOOL_PINK,
			Blocks.WOOL_TEAL, Blocks.WOOL_BROWN]:
		for face in [1]:
			for i in 3:
				_face_line(face, 0.0, 0.25 * (i + 1) - 0.06, 1.0, 0.25 * (i + 1), faint, size.x * 0.03)
	elif b in [Blocks.GOLD, Blocks.DIAMOND, 141, 142, 143, 144, 145, 146, Blocks.STEEL]:
		for face in [1]:
			_face_quad(face, 0.28, 0.28, 0.72, 0.72, Color(side.lightened(0.35), 0.9))
			_face_quad(face, 0.38, 0.38, 0.62, 0.62, Color(side.darkened(0.15), 0.9))
	elif b == Blocks.MAGMA:
		for i in 3:
			_face_line(1, 0.1 + 0.2 * i, 0.15, 0.35 + 0.25 * i, 0.85,
				Color(0.95, 0.45, 0.15, 0.9), size.x * 0.03)
			_face_line(2, 0.15 + 0.25 * i, 0.2, 0.3 + 0.2 * i, 0.9,
				Color(0.95, 0.45, 0.15, 0.9), size.x * 0.03)
	elif b in [Blocks.ICE, 134, 135]:
		_face_line(1, 0.15, 0.2, 0.6, 0.7, lite, size.x * 0.02)
		_face_line(2, 0.4, 0.15, 0.75, 0.8, lite, size.x * 0.02)
		_face_line(0, 0.2, 0.6, 0.8, 0.35, lite, size.x * 0.02)
	elif b == Blocks.PUMPKIN:
		for face in [1]:
			for i in 3:
				_face_line(face, 0.25 + 0.25 * i, 0.05, 0.25 + 0.25 * i, 0.95,
					Color(side.darkened(0.3), 0.8), size.x * 0.03)
		_face_quad(0, 0.42, 0.42, 0.58, 0.58, Color("4f6a2f"))
	elif b == 137:
		for face in [1]:
			for i in 3:
				_face_line(face, 0.2 + 0.3 * i, 0.05, 0.2 + 0.3 * i, 0.95,
					Color("3f6a2c"), size.x * 0.045)
	elif b == 138:
		for face in [1]:
			for i in 3:
				_face_line(face, 0.0, 0.28 * (i + 1), 1.0, 0.28 * (i + 1),
					Color("9a7c2a"), size.x * 0.035)
		_face_quad(0, 0.1, 0.42, 0.9, 0.58, Color("9a7c2a"))
	elif b == 132:
		for face in [1]:
			for i in 4:
				_face_quad(face, 0.1 + 0.2 * i, 0.3, 0.24 + 0.2 * i, 0.7,
					[Color("b04030"), Color("3a6ab0"), Color("3f8a4f"), Color("caa53d")][i])
	elif b == Blocks.CRAFTING_TABLE:
		_face_quad(0, 0.14, 0.14, 0.86, 0.86, Color(0, 0, 0, 0.0))
		for i in 3:
			_face_line(0, 0.2 + 0.3 * i, 0.15, 0.2 + 0.3 * i, 0.85, dark, size.x * 0.02)
			_face_line(0, 0.15, 0.2 + 0.3 * i, 0.85, 0.2 + 0.3 * i, dark, size.x * 0.02)
		_face_quad(1, 0.15, 0.2, 0.45, 0.55, Color("b5975f"))
		_face_quad(2, 0.55, 0.2, 0.85, 0.55, Color("9aa0a8"))
	elif b == Blocks.CHEST:
		for face in [1]:
			_face_line(face, 0.0, 0.4, 1.0, 0.4, dark, size.x * 0.03)
		_face_quad(2, 0.4, 0.3, 0.6, 0.55, Color("6c6f78"))
		_face_quad(1, 0.4, 0.3, 0.6, 0.55, Color("6c6f78"))
	elif b == Blocks.FURNACE:
		_face_quad(2, 0.2, 0.35, 0.8, 0.85, Color(0.08, 0.08, 0.1, 0.95))
		_face_quad(2, 0.3, 0.55, 0.7, 0.8, Color("ff7a3d"))
		_face_line(1, 0.2, 0.3, 0.8, 0.3, dark, size.x * 0.03)
	elif b in [Blocks.MARBLE, 114, 115, 111, Blocks.SLATE, 104, 106]:
		_face_line(1, 0.15, 0.25, 0.7, 0.6, faint, size.x * 0.02)
		_face_line(2, 0.3, 0.4, 0.85, 0.7, faint, size.x * 0.02)
		_face_line(0, 0.2, 0.55, 0.75, 0.3, faint, size.x * 0.02)
	elif b in [Blocks.SANDSTONE, 116]:
		for face in [1]:
			_face_line(face, 0.0, 0.35, 1.0, 0.35, faint, size.x * 0.025)
			_face_line(face, 0.0, 0.7, 1.0, 0.7, faint, size.x * 0.025)
	elif b in [108, 110, 112, Blocks.CHARRED]:
		for face in [1]:
			for i in 2:
				_face_line(face, 0.15 + 0.5 * i, 0.1, 0.3 + 0.5 * i, 0.9, faint, size.x * 0.02)
	elif b in [Blocks.STONE, 105, 110, Blocks.SLATE, Blocks.MYCELIUM]:
		for i in 5:
			draw_circle(_face_pt(1, 0.12 + 0.76 * _hashf(float(i * 7 + b)),
				0.12 + 0.76 * _hashf(float(i * 3 + b + 1))), size.x * 0.022, dark)
	elif b == Blocks.PURPUR:
		for pu in [0.16, 0.56]:
			for pv in [0.16, 0.56]:
				_face_quad(1, pu, pv, pu + 0.28, pv + 0.28, Color(0, 0, 0, 0.16))
				_face_quad(1, pu + 0.07, pv + 0.07, pu + 0.21, pv + 0.21,
					Color(1, 1, 1, 0.12))
	elif b == Blocks.SAND or b == 124 or b == Blocks.DIRT or b == Blocks.PATH:
		for face in [1]:
			for i in 4:
				draw_circle(_face_pt(face, 0.15 + 0.7 * _hashf(float(i * 3 + face)),
					0.15 + 0.7 * _hashf(float(i * 5 + face + 2))), size.x * 0.018, dark)

	# Material textures so the family blocks read as more than flat color.
	if block_id >= Blocks.M_STONE and block_id < Blocks.M_SOIL:
		for i in 6:
			draw_circle(mid + Vector2(sin(i * 2.4 + block_id) * w * 0.16,
				cos(i * 1.7 + block_id) * w * 0.13 + w * 0.04), w * 0.025, Color(0, 0, 0, 0.32))
	elif block_id >= Blocks.M_SOIL and block_id < Blocks.M_SNOW:
		for i in 3:
			var gy := h * (0.42 + i * 0.14)
			draw_line(Vector2(w * 0.3, gy), Vector2(w * 0.7, gy + w * 0.04),
				Color(0, 0, 0, 0.24), w * 0.03)
	elif block_id >= Blocks.M_STEEL and block_id < Blocks.M_STONE:
		for rivet in [Vector2(0.34, 0.38), Vector2(0.66, 0.38), Vector2(0.34, 0.72), Vector2(0.66, 0.72)]:
			draw_circle(Vector2(w * rivet.x, h * rivet.y), w * 0.028, Color(1, 1, 1, 0.4))
	elif block_id >= Blocks.M_SNOW and block_id < Blocks.MAX_BLOCK:
		for i in 3:
			var p := mid + Vector2(sin(i * 2.1 + block_id) * w * 0.15, cos(i * 2.8) * w * 0.12)
			draw_line(p - Vector2(w * 0.035, 0), p + Vector2(w * 0.035, 0), Color(1, 1, 1, 0.75), w * 0.02)
			draw_line(p - Vector2(0, w * 0.035), p + Vector2(0, w * 0.035), Color(1, 1, 1, 0.75), w * 0.02)
