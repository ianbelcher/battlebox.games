class_name GameModes
extends Object
## THE REGISTRY: every game this platform can play, in the order the
## front page offers them. Adding a mode is adding a line here (and its
## key to lobby.py's MODES, which validates on the way in).

static var ALL: Array = [BuildMode.new(), BattleMode.new(), CtfMode.new(),
	HoldoutMode.new()]

## The mode for a key, or Just building for a key nobody has written —
## which is what an unconfigured room has always been.
static func by_key(key: String) -> GameMode:
	for mode: GameMode in ALL:
		if mode.key == key:
			return mode
	return ALL[0]

static func has(key: String) -> bool:
	for mode: GameMode in ALL:
		if mode.key == key:
			return true
	return false

static func keys() -> Array:
	var out: Array = []
	for mode: GameMode in ALL:
		out.append(mode.key)
	return out

## The front page's table: key, label and the one line under it.
static func table() -> Array:
	var out: Array = []
	for mode: GameMode in ALL:
		out.append({"key": mode.key, "label": mode.label, "note": mode.note})
	return out
