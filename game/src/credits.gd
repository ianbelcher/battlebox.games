class_name Credits
## Who made the art we didn't. Shown on the world menu's Credits page.
##
## ADD AN ENTRY whenever a new pack or build goes in — especially for
## imported Minecraft builds, where each one belongs to the person who
## built it. "license" should be the actual licence name, and "url" the
## page it came from, so anyone can check our working.

const ENTRIES := [
	{"group": "Art packs", "name": "Kenney Game Assets",
		"by": "Kenney (kenney.nl)", "license": "CC0",
		"what": "Blocky Characters, Cube Pets, Blaster Kit, Nature Kit, sounds"},
	{"group": "Fonts", "name": "Barlow and Barlow Condensed",
		"by": "Jeremy Tribby", "license": "SIL Open Font License 1.1",
		"what": "The interface typeface, and the one the titles are set in"},
	{"group": "Fonts", "name": "DejaVu Sans",
		"by": "DejaVu fonts project", "license": "Bitstream Vera / public domain",
		"what": "Symbols the interface typeface does not have"},
	{"group": "Fonts", "name": "Noto Emoji / Noto Sans Symbols",
		"by": "Google", "license": "SIL Open Font License 1.1",
		"what": "The rest of the symbols, and emoji in typed names"},
	{"group": "Engine", "name": "Godot Engine",
		"by": "Juan Linietsky, Ariel Manzur and contributors",
		"license": "MIT", "what": "The engine this runs on"},
]

## Imported Minecraft builds, read straight off the generated kit file so
## the credits can never drift from what actually ships: one entry per
## build, naming its builder and licence.
static var _builds: Array = []

static func builds() -> Array:
	if _builds.is_empty():
		for kit: Dictionary in StructuresImported.KITS:
			_builds.append({"name": str(kit.name), "by": str(kit.by),
				"license": str(kit.license)})
	return _builds

static func groups() -> Array:
	var seen: Array = []
	for entry: Dictionary in ENTRIES:
		if not seen.has(str(entry.group)):
			seen.append(str(entry.group))
	return seen

static func in_group(group: String) -> Array:
	var out: Array = []
	for entry: Dictionary in ENTRIES:
		if str(entry.group) == group:
			out.append(entry)
	return out
