extends TestCase
## The maps' fast path has to draw exactly what the slow one did.
##
## The radar and the big map used to rotate a Vector2 and call set_pixel
## for every pixel, and were rewritten to cost a fraction of that (see
## MapPixels). Both halves of the rewrite are arithmetic that is
## easy to get subtly wrong — a sign on the rotation mirrors the radar, a
## byte order swaps red and blue — and neither would fail anything else.

func test_the_expanded_rotation_is_the_rotation() -> void:
	var center := Vector3(37.4, 20.0, -112.9)
	for yaw: float in [0.0, 0.7, 2.5, -1.2, PI]:
		for span: float in [0.75, 1.5]:
			for eye_row: float in [64.0, 89.6]:
				for py: int in [0, 31, 64, 127]:
					var row := MapPixels.radar_row(center, yaw, span, eye_row, py)
					for px: int in [0, 17, 64, 127]:
						var off := Vector2(float(px) - 64.0,
							float(py) - eye_row).rotated(-yaw) * span
						between(row.x + float(px) * row.z - (center.x + off.x),
							-0.001, 0.001, "x at yaw %.2f px %d py %d" % [yaw, px, py])
						between(row.y + float(px) * row.w - (center.z + off.y),
							-0.001, 0.001, "z at yaw %.2f px %d py %d" % [yaw, px, py])

func test_a_pixel_comes_back_as_the_colour_it_was() -> void:
	# Opaque alpha is the top bit of the int: the case a signed 32-bit
	# array could mangle.
	for colour: Color in [Color(0.06, 0.07, 0.1), Color(1, 0, 0), Color(0, 0, 1),
			Color(0.42, 0.55, 0.31)]:
		var pixels := PackedInt32Array([MapPixels.rgba(colour)])
		var back := MapPixels.image_of(1, pixels).get_pixel(0, 0)
		between(back.r - colour.r, -0.003, 0.003, "red of %s" % colour)
		between(back.g - colour.g, -0.003, 0.003, "green of %s" % colour)
		between(back.b - colour.b, -0.003, 0.003, "blue of %s" % colour)
		equal(back.a, 1.0, "opaque")

func test_every_block_has_its_washed_out_colour() -> void:
	var wash := MapPixels.wash_table()
	equal(wash.size(), Blocks.ID_COUNT, "one entry per block id")
	var pixels := PackedInt32Array([wash[Blocks.GRASS]])
	var back := MapPixels.image_of(1, pixels).get_pixel(0, 0)
	var grey := Blocks.top_color_of(Blocks.GRASS).get_luminance()
	between(back.r - (grey * 0.42 + 0.10), -0.003, 0.003, "grass is the grass wash")
	between(back.b - (grey * 0.48 + 0.14), -0.003, 0.003, "and blue-tinted")
