class_name MapPixels
extends RefCounted
## The arithmetic under the radar and the big map (MiniMap), kept apart
## from it so a unit test can reach it: MiniMap needs the Game autoload,
## and a --script test run has none.
##
## THE MAPS USED TO BE THE JANK. Each pixel did a dictionary lookup for
## its chunk, fetched the block's info dictionary, made a Color, took its
## luminance and called set_pixel — about 3 µs a pixel, so 40-60 ms for
## one 128x128 radar on a fast desktop. Every player's radar does that
## every 0.3 s, and the two timers of a two-player split screen fire in
## the same frame: a regular 100 ms hitch on a machine that otherwise ran
## a frame in under 2. The per-pixel work is now a table read and one int
## write.

## Every block id's washed-out map colour, as an rgba() pixel. Washed out
## on purpose: at full colour, with per-block noise on top, the maps were
## a speckled mess you could not read anything off. A low-contrast
## grey-blue wash still shows coastlines and buildings, and leaves the
## players as the only strong colours.
static var _wash := PackedInt32Array()

static func wash_table() -> PackedInt32Array:
	if _wash.is_empty():
		_wash.resize(Blocks.ID_COUNT)
		for id in Blocks.ID_COUNT:
			var grey := Blocks.top_color_of(id).get_luminance()
			_wash[id] = rgba(Color(grey * 0.42 + 0.10, grey * 0.44 + 0.11,
				grey * 0.48 + 0.14))
	return _wash

## A colour as one pixel of a PackedInt32Array that image_of() turns into
## an RGBA8 image (little-endian: red in the low byte).
static func rgba(c: Color) -> int:
	return c.to_abgr32()

## A square RGBA8 image from rgba() pixels, row by row.
static func image_of(side: int, pixels: PackedInt32Array) -> Image:
	return Image.create_from_data(side, side, false, Image.FORMAT_RGBA8,
		pixels.to_byte_array())

## Where row `py` of the 128x128 radar starts in the world and how far one
## pixel steps along it, as (x, z, step x, step z): pixel px of the row is
## (x + px * step x, z + px * step z). That is
## Vector2(px - 64, py - eye_row).rotated(-yaw) * span from `center`,
## expanded so each pixel is two multiply-adds instead of a rotation.
static func radar_row(center: Vector3, yaw: float, span: float, eye_row: float,
		py: int) -> Vector4:
	var step_x := cos(yaw) * span
	var step_z := -sin(yaw) * span
	var dy := float(py) - eye_row
	return Vector4(center.x - 64.0 * step_x - dy * step_z,
		center.z - 64.0 * step_z + dy * step_x, step_x, step_z)
