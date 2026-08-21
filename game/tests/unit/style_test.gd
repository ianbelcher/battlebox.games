extends TestCase
## House style, checked rather than hoped for.
##
## Not a linter — gdlint does that job better and CONTRIBUTING points at
## it. These are the few rules this codebase actually cares about, the
## ones a reviewer would otherwise have to notice by eye, and each is here
## because letting it slide costs something specific.

const SOURCE_DIRS := ["res://src", "res://tests/unit", "res://tests"]
## Long enough for the wide table literals in blocks.gd and creatures.gd,
## short enough to sit side by side in a split editor.
const MAX_LINE := 120
## Written by a tool, not a person. Reformatting generated output only
## means the next regeneration undoes it.
const GENERATED := ["res://src/structures_imported.gd"]

func test_every_script_says_what_it_is_for() -> void:
	# The doc comment on a script is the first thing anyone opening it
	# reads, and this repository's comments are the most valuable thing in
	# it. A file without one is a file somebody has to reverse-engineer.
	for path: String in _scripts():
		var lines := FileAccess.get_file_as_string(path).split("\n")
		var found := false
		for i in mini(4, lines.size()):
			if str(lines[i]).begins_with("## "):
				found = true
				break
		check(found, "%s has no doc comment in its first four lines" % path)

func test_indentation_is_tabs() -> void:
	# Godot's own convention, and mixing the two makes a diff unreadable.
	for path: String in _scripts():
		var line_number := 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			line_number += 1
			if line.begins_with(" ") and not line.strip_edges().begins_with("#"):
				fail("%s:%d is indented with spaces" % [path, line_number])
				break

func test_no_line_is_absurdly_long() -> void:
	for path: String in _scripts():
		if path in GENERATED:
			continue
		var line_number := 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			line_number += 1
			if line.length() > MAX_LINE:
				fail("%s:%d is %d characters (limit %d)"
					% [path, line_number, line.length(), MAX_LINE])
				break

func test_no_trailing_whitespace() -> void:
	for path: String in _scripts():
		var line_number := 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			line_number += 1
			if line != line.rstrip(" \t"):
				fail("%s:%d has trailing whitespace" % [path, line_number])
				break

func test_no_rpc_lives_outside_the_world_node() -> void:
	# THE architectural rule of the server. Every @rpc is declared in
	# world.gd, so one file describes the whole wire protocol and no call
	# ever has to resolve against a node path that exists on one side and
	# not the other. game.gd owns the roster and has its own handful.
	const ALLOWED := ["res://src/world.gd", "res://src/game.gd"]
	for path: String in _scripts():
		if path in ALLOWED:
			continue
		# At the START of a line: an annotation, not a doc comment saying
		# there isn't one. Matching anywhere reported every director,
		# because each of their headers explains this very rule.
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with("@rpc"):
				fail("%s declares an @rpc. Every RPC belongs in world.gd — " % path
					+ "see docs/architecture.md for why")
				break

func test_no_script_has_grown_past_the_point_of_being_readable() -> void:
	# A ceiling, not a target. world.gd was 6,255 lines before it was split
	# into a wire protocol and eight directors; this is what stops the next
	# one getting there unnoticed.
	const MAX_LINES := 3200
	for path: String in _scripts():
		var count := FileAccess.get_file_as_string(path).split("\n").size()
		check(count <= MAX_LINES,
			"%s is %d lines. Split it — see docs/architecture.md" % [path, count])

func _scripts() -> Array[String]:
	var found: Array[String] = []
	for dir_path: String in SOURCE_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name: String in dir.get_files():
			var clean := file_name.replace(".remap", "")
			if clean.ends_with(".gd"):
				found.append("%s/%s" % [dir_path, clean])
	found.sort()
	return found
