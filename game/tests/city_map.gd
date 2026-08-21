extends SceneTree
## Top-down snapshot of a generated theme, for eyeballing a map generator
## without launching the game.
##   WORLD_MAP_OUT=/tmp/city.png WORLD_MAP_THEME=city WORLD_MAP_SPAN=6 \
##   godot --headless --path <game> --script res://tests/city_map.gd
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
					for y in range(WorldGen.CHUNK_H - 1, -1, -1):
						var b := data[WorldGen.idx(lx, y, lz)]
						if b != Blocks.AIR:
							top = y
							block = b
							break
					var col := Blocks.color_of(block)
					# Shade by height so the skyline reads.
					col = col.darkened(clampf(1.0 - float(top) / 60.0, 0.0, 0.6))
					img.set_pixel(cx * WorldGen.CHUNK_SIZE + lx,
						cz * WorldGen.CHUNK_SIZE + lz, col)
	if zoom > 1:
		img.resize(size * zoom, size * zoom, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	print("wrote ", out, " ", size, "x", size)
	quit()
