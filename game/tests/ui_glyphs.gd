extends SceneTree
## EVERY SYMBOL THE UI USES CAN ACTUALLY BE DRAWN.
##
##   godot --headless --path <game> --script res://tests/ui_glyphs.gd
##
## The game shipped no font for years and nobody noticed, because on a
## desktop Godot quietly borrows missing glyphs from the operating
## system's fonts. A browser has none to borrow, so all 51 symbols the
## menus are built from — hearts, the ⒶⒷⓍⓎ button caps, the trophy, the
## weather — drew as empty boxes with their code point inside. The hearts
## read as "2665".
##
## So three fonts are bundled now. This checks they actually cover what
## the UI asks for, and it works out what the UI asks for by READING THE
## SOURCE rather than from a list somebody has to remember to update.
## That matters: a hand-written list would still pass on the day someone
## adds a new emoji to a menu, which is precisely the day it should fail.
##
## Picking the fonts by eye would not have worked either. DejaVu looks
## like the obvious choice and is missing every circled letter; Noto Sans
## Symbols 2 sounds like the fix for that and does not have them either.
## Only Noto Sans Symbols does.

const FONTS := [
	"res://assets/fonts/DejaVuSans.ttf",
	"res://assets/fonts/NotoSansSymbols-Regular.ttf",
	"res://assets/fonts/NotoEmoji-Regular.ttf",
]

## Scanned from here — the UI code. Not the whole project: world
## generation and tests have no glyphs a player ever sees.
const SOURCES := "res://src"

func _initialize() -> void:
	var fonts: Array[Font] = []
	for path: String in FONTS:
		var font := load(path) as Font
		if font == null:
			print("ui_glyphs: FAIL — could not load %s" % path)
			quit(1)
			return
		fonts.append(font)

	var wanted := _glyphs_in_source()
	# A run that measured nothing is a failure. If the scan ever breaks,
	# this must not report a cheerful pass over an empty set.
	if wanted.size() < 20:
		print("ui_glyphs: FAIL — only found %d symbols in %s; the scan is broken"
			% [wanted.size(), SOURCES])
		quit(1)
		return

	var missing: Array[String] = []
	for code: int in wanted:
		var covered := false
		for font: Font in fonts:
			if font.has_char(code):
				covered = true
				break
		if not covered:
			missing.append("U+%04X %s" % [code, String.chr(code)])

	if missing.is_empty():
		print("ui_glyphs: PASS — all %d symbols the UI uses can be drawn"
			% wanted.size())
		quit(0)
	else:
		print("ui_glyphs: FAIL — %d symbols no bundled font can draw:"
			% missing.size())
		for entry: String in missing:
			print("  " + entry)
		print("  (these will render as boxes in the browser — find a font "
			+ "that has them, or use a different symbol)")
		quit(1)

## Every non-ASCII character inside a double-quoted string in the UI
## source. Comments are skipped: prose about a symbol is not the UI using
## one, and this file's own header would otherwise fail its own test.
func _glyphs_in_source() -> Array[int]:
	var found := {}
	for file: String in _gd_files(SOURCES):
		var text := FileAccess.get_file_as_string(file)
		for line: String in text.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			var in_string := false
			for i in line.length():
				var ch := line[i]
				if ch == '"':
					in_string = not in_string
					continue
				if in_string and ch.unicode_at(0) > 0x7F:
					found[ch.unicode_at(0)] = true
	var codes: Array[int] = []
	for code: int in found:
		codes.append(code)
	codes.sort()
	return codes

func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".gd"):
			out.append(dir_path + "/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	return out
