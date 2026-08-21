extends TestCase
## The environment-variable registry has to describe reality.
##
## Sixty-odd hooks read straight out of the environment, scattered across
## the files that care about them. That is the right place for them, but it
## means the only list of what this project responds to is EnvConfig.KNOWN
## — and a list maintained by hand is a list that is wrong.
##
## So this reads the source instead of trusting the list, and fails on the
## day a hook is added without a line saying what it does.

const SOURCE_DIRS := ["res://src", "res://tests", "res://tests/unit"]
## A read of the environment: the raw call, or one of EnvConfig's typed
## readers. Digits are in the class because of WORLD_MCA_Y0 — leaving them
## out was a bug this test had, and caught in itself.
const CALL := "(?:OS\\.get_environment|EnvConfig\\.(?:text|flag|number|decimal|has))\\(\"([A-Z0-9_]+)\""

func test_every_variable_the_code_reads_is_documented() -> void:
	var found := _scan()
	check(not found.is_empty(), "the scan found some variables at all")
	for name: String in found.keys():
		check(EnvConfig.KNOWN.has(name),
			"%s is read in %s but is not in EnvConfig.KNOWN — add a line "
			% [name, found[name]] + "saying what it does")

func test_the_registry_does_not_describe_variables_nobody_reads() -> void:
	# The other direction, which rots more quietly: a hook is deleted and
	# its documentation lives on, describing a switch that does nothing.
	var found := _scan()
	for name: String in EnvConfig.KNOWN.keys():
		check(found.has(name),
			"EnvConfig.KNOWN documents %s but nothing reads it" % name)

func test_every_entry_actually_says_something() -> void:
	for name: String in EnvConfig.KNOWN.keys():
		var described := str(EnvConfig.KNOWN[name])
		check(described.length() >= 12,
			"%s's description is too short to be useful: %s" % [name, described])
		check(described.strip_edges() == described,
			"%s's description has stray whitespace" % name)

func test_names_are_sorted_and_complete() -> void:
	var listed := EnvConfig.names()
	equal(listed.size(), EnvConfig.KNOWN.size(), "names() lists every entry")
	var sorted_copy := listed.duplicate()
	sorted_copy.sort()
	equal(listed, sorted_copy, "names() comes back sorted")

func test_readers_fall_back_rather_than_returning_nonsense() -> void:
	# Nothing sets these, so every reader is on its fallback path — which
	# is the path that runs on a real server, and the one worth checking.
	equal(EnvConfig.text("WORLD_NOT_SET_ANYWHERE", "fallback"), "fallback",
		"text() falls back when unset")
	equal(EnvConfig.number("WORLD_NOT_SET_ANYWHERE", 7), 7,
		"number() falls back when unset")
	equal(EnvConfig.decimal("WORLD_NOT_SET_ANYWHERE", 1.5), 1.5,
		"decimal() falls back when unset")
	check(not EnvConfig.flag("WORLD_NOT_SET_ANYWHERE"), "flag() is off when unset")
	check(not EnvConfig.has("WORLD_NOT_SET_ANYWHERE"), "has() is false when unset")

## name -> the file it was found in.
func _scan() -> Dictionary:
	var pattern := RegEx.new()
	pattern.compile(CALL)
	var found := {}
	for dir_path: String in SOURCE_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name: String in dir.get_files():
			var clean := file_name.replace(".remap", "")
			if not clean.ends_with(".gd"):
				continue
			# This file, and only this file, names variables that are
			# deliberately not real: the fallback checks need one nothing
			# sets. Scanning itself would report those as undocumented.
			if clean == "env_config_test.gd":
				continue
			var path := "%s/%s" % [dir_path, clean]
			var text := FileAccess.get_file_as_string(path)
			if text.is_empty():
				continue
			for hit: RegExMatch in pattern.search_all(_code_only(text)):
				found[hit.get_string(1)] = path
	return found

## Comments do not read anything. Without this, a doc comment that quotes
## the shape of the call — as the one above CALL does — reads as a hook.
static func _code_only(text: String) -> String:
	var out := ""
	for line: String in text.split("\n"):
		var quote := line.find("\"")
		var hash_at := line.find("#")
		# A # inside a string is not a comment; the only # that starts one
		# is the first one that comes before any quote.
		if hash_at >= 0 and (quote < 0 or hash_at < quote):
			out += line.substr(0, hash_at) + "\n"
		else:
			out += line + "\n"
	return out
