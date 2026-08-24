extends SceneTree
## THE SOUNDS THAT COME OUT OF FILES ACTUALLY CAME OUT OF FILES.
##
## A missing or misnamed sample fails silently: Sfx falls back to the
## synthesised version, the game still makes a noise, and nothing anywhere
## says the recording never loaded. The explosions were synthesised twice
## and rejected twice, so "did the real one load" is worth asking out loud.
##
##     godot --headless --path game --script res://tests/sfx_samples.gd

## Explosions are NOT in here on purpose — they are synthesised, and the
## recordings that briefly replaced them were taken straight back out.
## See the note above Sfx.SAMPLES.
const WANTED := {
	"dig": 5,
	"bonk": 3,
	"place": 4,
	"land": 3,
}

func _initialize() -> void:
	var sfx: Node = load("res://src/sfx.gd").new()
	get_root().add_child(sfx)
	await process_frame
	var bad: PackedStringArray = []
	for clip: String in WANTED:
		var got: Variant = sfx._streams.get(clip)
		if got == null:
			bad.append("%s: nothing registered at all" % clip)
			continue
		if not (got is Array):
			bad.append("%s: synthesised, not the recording — the file did not load"
				% clip)
			continue
		var variants: Array = got
		if variants.size() != int(WANTED[clip]):
			bad.append("%s: %d variants, expected %d"
				% [clip, variants.size(), WANTED[clip]])
		for v: Variant in variants:
			if not (v is AudioStream):
				bad.append("%s: a variant is not an AudioStream" % clip)
	for line: String in bad:
		print("  FAIL  %s" % line)
	if bad.is_empty():
		print("sfx_samples: PASS — %d clips play recordings, not fallbacks"
			% WANTED.size())
		quit(0)
	else:
		print("sfx_samples: FAILED")
		quit(1)
