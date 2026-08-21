extends SceneTree
## The capture-the-flag beacons: one glowing, unbreakable block per team
## colour, and the ids line up with WorldNode.TEAM_WOOL.
##
## This exists because all three of those properties are invisible until
## somebody is standing in front of a flag in a live round. Lose the
## `unbreakable` flag and the beacon can be dug away; lose the glow and it
## stops being findable after dark; renumber the ids and every team's pole
## comes out the wrong colour — and a wrong colour here is worse than no
## colour, because you charge your own base.
##
## `Blocks` is plain data with no autoloads behind it, so it is one of the
## few things a `--script` run can actually load. Keep it that way: this
## test deliberately does NOT reach for WorldNode.
##
##     godot --headless --path game --script res://tests/flag_beacons.gd

## The team colours, in order, as world.gd's TEAM_WOOL lists them. Copied
## rather than imported for the reason above; if the two ever disagree the
## names below are what a player sees on the field.
const TEAM_ORDER := ["Red", "Blue", "Green", "Yellow", "Purple", "Orange",
	"Teal", "Pink"]

func _initialize() -> void:
	var failures: PackedStringArray = []
	var checked := 0

	for i in TEAM_ORDER.size():
		var id: int = Blocks.BEACON_TEAM + i
		var info := Blocks.info(id)
		var want := str(TEAM_ORDER[i])
		checked += 1
		if info.is_empty() or not info.has("name"):
			failures.append("beacon %d (%s) has no palette entry" % [id, want])
			continue
		if not str(info.name).begins_with(want):
			failures.append("beacon %d is %s, expected %s"
				% [id, info.name, want])
		if Blocks.is_breakable(id):
			failures.append("%s beacon is BREAKABLE — the flag can be dug away"
				% want)
		if Blocks.emit_of(id) <= 1.0:
			failures.append("%s beacon barely emits (%.2f) — it will not read"
				% [want, Blocks.emit_of(id)])
		if Blocks.light_of(id) <= 0.0:
			failures.append("%s beacon casts no light" % want)
		if not Blocks.is_solid(id):
			failures.append("%s beacon is not solid" % want)

	# A block id is one byte. If the beacons ever run past 255 they wrap
	# into other blocks and chunks start decoding as nonsense.
	var top: int = Blocks.BEACON_TEAM + TEAM_ORDER.size() - 1
	if top > 255:
		failures.append("beacons run to id %d, past the one-byte ceiling" % top)

	# Nothing else may share these ids.
	for i in TEAM_ORDER.size():
		var id: int = Blocks.BEACON_TEAM + i
		if id <= Blocks.MYCELIUM:
			failures.append("beacon %d collides with the ordinary palette" % id)

	if failures.is_empty():
		print("flag_beacons: PASS — %d beacons, all glowing and unbreakable"
			% checked)
		quit(0)
		return
	for line in failures:
		print("flag_beacons: FAIL — " + line)
	quit(1)
