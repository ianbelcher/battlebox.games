class_name QuickPlay
## WHICH GAME "PLAY" PUTS YOU IN.
##
## The front page's big button used to be "Start a game", which opened a
## sheet of ten questions. That is the right screen for somebody setting a
## game up and the wrong one for somebody who just wants to play — and
## in every game of this shape the first button is the one that finds you
## a match. So Play picks a public game and goes, and the questions are a
## second button away for whoever wants them.
##
## THE PICK IS A TABLE, NOT A MOOD: the game with the most people in it,
## because that is the one worth joining; on a tie the always-open one,
## because it is never going to close under you; then the fuller of the
## rest. Pure, so tests/unit/quick_play_test.gd can ask it directly.

## The room to join out of a lobby listing, or {} when there is nothing
## listed at all — in which case the caller falls back to the always-open
## game by its fixed code, which works whether or not the list ever came.
static func choose(rooms: Array, house_code: String) -> Dictionary:
	var best: Dictionary = {}
	var best_key: Array = []
	for entry: Variant in rooms:
		if not (entry is Dictionary):
			continue
		var room: Dictionary = entry
		if str(room.get("code", "")).is_empty():
			continue
		var key := _rank(room, house_code)
		if best.is_empty() or _better(key, best_key):
			best = room
			best_key = key
	return best

## Higher is better, compared element by element: people, then the house,
## then anybody at all (computer players included), then youngest.
static func _rank(room: Dictionary, house_code: String) -> Array:
	var humans := int(room.get("humans", room.get("players", 0)))
	var house := 1 if str(room.get("code", "")) == house_code \
		or bool(room.get("house", false)) else 0
	return [humans, house, int(room.get("players", 0)), -int(room.get("age", 0))]

static func _better(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if int(a[i]) != int(b[i]):
			return int(a[i]) > int(b[i])
	return false

## One line saying where Play will take you: the game's name, what it is,
## and whether anybody is in it — so the button never drops somebody into
## a world nothing on the screen described.
static func describe(room: Dictionary) -> String:
	var name := str(room.get("name", room.get("code", "")))
	var parts: Array = [name]
	var what := GameSetup.summary(room.get("settings", {}))
	if not what.is_empty():
		parts.append(what)
	var humans := int(room.get("humans", room.get("players", 0)))
	if humans == 1:
		parts.append("1 playing")
	elif humans > 1:
		parts.append("%d playing" % humans)
	else:
		parts.append("waiting for you")
	return " · ".join(parts)
