extends SceneTree
## Top-down snapshot of a generated theme, for eyeballing a map generator
## without launching the game.
##   WORLD_MAP_OUT=/tmp/city.png WORLD_MAP_THEME=city WORLD_MAP_SPAN=6 \
##   godot --headless --path <game> --script res://tests/city_map.gd
##
## WORLD_MAP_Y=<y> slices at one level rather than looking down on the
## roof — which is the only way to see an interior like the office.
func _initialize() -> void:
	var theme := OS.get_environment("WORLD_MAP_THEME")
	if theme.is_empty():
		theme = "city"
	var span := int(OS.get_environment("WORLD_MAP_SPAN")) if \
		OS.get_environment("WORLD_MAP_SPAN") != "" else 6
	var out := OS.get_environment("WORLD_MAP_OUT")
	if out.is_empty():
		out = "/tmp/map.png"
	var zoom := int(OS.get_environment("WORLD_MAP_ZOOM")) if \
		OS.get_environment("WORLD_MAP_ZOOM") != "" else 1
	var size_env := OS.get_environment("WORLD_MAP_SIZE")
	var gen := WorldGen.new(20260726, theme,
		size_env.to_int() if size_env.is_valid_int() else 250)
	# WORLD_MAP_Y=<y> cuts a horizontal slice at that level instead of
	# looking down on the roof.
	var slice_env := OS.get_environment("WORLD_MAP_Y")
	var slice_y := slice_env.to_int() if slice_env.is_valid_int() else -1
	var size := span * WorldGen.CHUNK_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	# Render centred on the origin so the square slab's edges are visible.
	var first := -span / 2
	for cz in span:
		for cx in span:
			var data := gen.generate_chunk(first + cx, first + cz)
			for lz in WorldGen.CHUNK_SIZE:
				for lx in WorldGen.CHUNK_SIZE:
					var top := 0
					var block := 0
					if slice_y >= 0:
						# ONE LEVEL, not the roof. An interior — the
						# office floor plate — is entirely hidden under
						# its own ceiling from above, so the only useful
						# picture of it is a horizontal cut.
						top = slice_y
						block = data.decode_u16(WorldGen.bidx(lx, slice_y, lz))
					else:
						for y in range(WorldGen.CHUNK_H - 1, -1, -1):
							var b := data.decode_u16(WorldGen.bidx(lx, y, lz))
							if b != Blocks.AIR:
								top = y
								block = b
								break
					var col := Blocks.color_of(block)
					# Shade by height so the skyline reads — but only when
					# the picture IS a skyline. A slice is all one level,
					# and shading it by that level just dims the lot.
					if slice_y < 0:
						col = col.darkened(clampf(1.0 - float(top) / 60.0, 0.0, 0.6))
					img.set_pixel(cx * WorldGen.CHUNK_SIZE + lx,
						cz * WorldGen.CHUNK_SIZE + lz, col)
	if zoom > 1:
		img.resize(size * zoom, size * zoom, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	print("wrote ", out, " ", size, "x", size)
	quit()
