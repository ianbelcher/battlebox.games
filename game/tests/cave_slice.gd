extends SceneTree
## A CROSS-SECTION OF THE UNDERGROUND, as a picture.
##
##   WORLD_MAP_THEME=caverns WORLD_MAP_OUT=/tmp/slice.png \
##   godot --headless --path <game> --script res://tests/cave_slice.gd
##
## The map renders (city_map.gd) look straight down, which is exactly the
## view that cannot see a cave. This generates a strip of chunks and draws
## one vertical slice through them, every block a pixel, x across and y
## up: stone dark, air black, water blue, and the things that glow in
## their own colour. It exists because "make the caves bigger" is a change
## whose only other check is digging a hole and hoping.
##
## WORLD_MAP_SPAN chunks either side of the origin (default 8); the slice
## is taken at world z = WORLD_SLICE_Z (default 8; 24 cuts through a
## caverns-world shaft). Prints how much of the
## underground is open, which is the number that "bigger" means.

func _initialize() -> void:
	var theme := OS.get_environment("WORLD_MAP_THEME")
	if theme.is_empty():
		theme = "classic"
	var span := 8
	if OS.get_environment("WORLD_MAP_SPAN").is_valid_int():
		span = int(OS.get_environment("WORLD_MAP_SPAN"))
	var slice_z := 8
	if OS.get_environment("WORLD_SLICE_Z").is_valid_int():
		slice_z = int(OS.get_environment("WORLD_SLICE_Z"))
	var out := OS.get_environment("WORLD_MAP_OUT")
	if out.is_empty():
		out = "/tmp/slice.png"
	var gen := WorldGen.new(20260726, theme, span * 2 * WorldGen.CHUNK_SIZE)
	var cz := int(floor(float(slice_z) / float(WorldGen.CHUNK_SIZE)))
	var lz := slice_z - cz * WorldGen.CHUNK_SIZE
	var width := span * 2 * WorldGen.CHUNK_SIZE
	var image := Image.create(width, WorldGen.CHUNK_H, false, Image.FORMAT_RGB8)
	var open := 0
	var below := 0
	for cx in range(-span, span):
		var data := gen.generate_chunk(cx, cz)
		var h_here := gen.height_at(cx * WorldGen.CHUNK_SIZE + 8, slice_z)
		for lx in WorldGen.CHUNK_SIZE:
			var px := (cx + span) * WorldGen.CHUNK_SIZE + lx
			for y in WorldGen.CHUNK_H:
				var block := data[WorldGen.idx(lx, y, lz)]
				var c := Color(0.02, 0.02, 0.03)
				if block == Blocks.AIR:
					c = Color(0.02, 0.02, 0.03) if y < h_here else Color(0.10, 0.12, 0.18)
				elif block == Blocks.WATER:
					c = Color(0.15, 0.35, 0.8)
				elif Blocks.LK_EMIT[block] > 0.5:
					c = Blocks.color_of(block).lightened(0.2)
				else:
					c = Blocks.color_of(block).darkened(0.35)
				image.set_pixel(px, WorldGen.CHUNK_H - 1 - y, c)
				if y >= 4 and y < h_here - 3:
					below += 1
					if block == Blocks.AIR or block == Blocks.WATER:
						open += 1
	# Four pixels a block, nearest-neighbour, or the picture is a strip
	# nobody can read.
	image.resize(width * 4, WorldGen.CHUNK_H * 4, Image.INTERPOLATE_NEAREST)
	image.save_png(out)
	print("cave_slice: %s — %.0f%% of the underground is open; wrote %s" % [
		theme, 100.0 * float(open) / maxf(1.0, float(below)), out])
	quit(0)
