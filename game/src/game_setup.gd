class_name GameSetup
## WHAT A NEW GAME CAN BE, in one table.
##
## Everything you could once only change from inside a running world — the
## mode, the map, how big it is, how long a round lasts, how many computer
## players are waiting in it — is chosen HERE, before the world exists.
##
## WHY THAT IS NOT THE SAME FEATURE MOVED SIDEWAYS. A world is generated
## at boot from its environment and never written to disk (see
## ChunkStore), so a map picked before the room starts is the map the
## terrain is MADE of. Picked afterwards it is a reset: everybody is
## stood down, the board is cleared and the world is rebuilt underneath
## them. The second one works, and it is what the world menu still does
## for a game already running — but it is a strange thing to make somebody
## do to get the game they wanted in the first place.
##
## THE SHAPE OF THIS FILE IS THE POINT. It is a table, and it is pure: no
## nodes, no network, no UI. lobby_screen.gd draws it, lobby.py validates
## a copy of the same rules on the way in, world.gd applies the result at
## boot, and tests/unit/game_setup_test.gd checks it. Adding a setting
## means adding a row here and one line to each of those — rather than
## finding the four places that would otherwise have invented their own
## list of maps and drifted apart by one entry.
##
## NEVER TRUST WHAT COMES BACK. clean() clamps everything to this table,
## and the lobby clamps again server-side, because a POST is a POST: the
## front page is not the only thing that can send one.

## The keys a settings dictionary holds. Anything else is dropped.
const FIELDS := ["mode", "map", "size", "minutes", "bots", "target",
	"revive", "drop"]

## HOW ARE WE PLAYING. `note` is the one line under the name on the tile —
## what the mode IS, in the words a child would use, not its rules.
const MODES := [
	{"key": "creative", "label": "Just building", "note": "No rounds, nobody gets knocked out"},
	{"key": "battle", "label": "Battle royale", "note": "Last one standing wins the round"},
	{"key": "ctf", "label": "Capture the flag", "note": "Take theirs, keep hold of yours"},
	{"key": "holdout", "label": "Last flag", "note": "Lose your flag and your team is out"},
]

## THE PROCEDURAL THEMES, and only those. A world imported from a
## Minecraft save (see mca.gd) lives in the SERVER's maps/ directory, so
## nothing on this screen can know it is there — the front page is talking
## to a room that does not exist yet. Those stay where they already work:
## the world menu, once you are in a game that has them.
const MAPS := [
	{"key": "classic", "label": "Island", "note": "Hills, trees, a bit of sea"},
	{"key": "desert", "label": "Desert", "note": "Open sand and canyons"},
	{"key": "isles", "label": "Isles", "note": "Scattered islands and water"},
	{"key": "castles", "label": "Castles", "note": "Ready-built keeps to fight over"},
	{"key": "city", "label": "City", "note": "Streets, blocks and rooftops"},
	{"key": "sky", "label": "Skylands", "note": "Floating ground, a long way down"},
	{"key": "space", "label": "Space", "note": "Low gravity, no sky"},
]

## HOW BIG, in blocks across. The same five the world menu offers, and
## they double each time on purpose: a row of near-identical numbers is a
## row nobody can choose from.
const SIZES := [
	{"value": 50, "label": "Tiny", "note": "50 across"},
	{"value": 100, "label": "Small", "note": "100 across"},
	{"value": 200, "label": "Medium", "note": "200 across"},
	{"value": 400, "label": "Big", "note": "400 across"},
	{"value": 800, "label": "Huge", "note": "800 across"},
]

## SOMEBODY TO PLAY AGAINST from the first second. A world with nobody in
## it is a field, and the first child in is alone in it until a grown-up
## finds the Players tab.
const BOT_COUNTS := [0, 3, 5, 10, 20]

## Captures to win, in capture the flag.
const TARGETS := [1, 3, 5, 10]

## Round lengths per mode, in minutes. Battle royale and last flag
## standing each already had their own list and they are NOT the same
## list — this keeps them apart rather than averaging them into one that
## suits neither.
const BATTLE_LENGTHS := [3, 5, 8, 60]
const UNLIMITED := 60

## THE NEUTRAL BASELINE, not what the New game screen opens on — see
## opening_choice(). It is creative because that is what a room created
## by anything OTHER than this screen has always been: the lobby's API
## takes a bare POST with no settings in it, and a script that has never
## heard of a mode must not suddenly get a battle royale with a storm
## closing in on it.
const DEFAULT_MODE := "creative"
const DEFAULT_MAP := "classic"
const DEFAULT_SIZE := 200
const DEFAULT_MINUTES := 5
const DEFAULT_BOTS := 5
const DEFAULT_TARGET := 3

## What a game is when nothing has been said about it. This is the
## FALLBACK — the value every field takes when it arrives missing or
## unreadable — and lobby.py's DEFAULT_SETTINGS is the same table.
static func defaults() -> Dictionary:
	return {
		"mode": DEFAULT_MODE,
		"map": DEFAULT_MAP,
		"size": DEFAULT_SIZE,
		"minutes": DEFAULT_MINUTES,
		"bots": DEFAULT_BOTS,
		"target": DEFAULT_TARGET,
		"revive": ReviveRule.MATES_AND_FLAG,
		"drop": false,
	}

## WHAT THE NEW GAME SCREEN OPENS ON, which is a different question from
## what a missing value falls back to.
##
## BATTLE ROYALE. Somebody who has just pressed "New game" has said they
## want a game, and the always-on world one button to the left of it is
## already the place to go and build in peace — so opening on "Just
## building" would offer them the thing they just walked past.
##
## It is a separate function rather than a different default because the
## fallback has a second reader with its own rules: a bare POST to the
## lobby is not somebody pressing New game, and it should not be handed a
## storm. See DEFAULT_MODE.
const OPENS_ON := "battle"

static func opening_choice() -> Dictionary:
	var out := defaults()
	out["mode"] = OPENS_ON
	return clean(out)

# ------------------------------------------------------------------
# Which settings a mode actually has
# ------------------------------------------------------------------

## Does this mode have knockouts at all? Everything about being put on
## the floor — reviving, dropping your weapons — is meaningless without
## them, and showing those settings in creative is offering an answer to
## a question the mode never asks.
static func has_knockouts(mode: String) -> bool:
	return mode != "creative"

## Does this mode have flags?
static func has_flags(mode: String) -> bool:
	return mode == "ctf" or mode == "holdout"

## Does a round of this mode run on a clock?
static func has_clock(mode: String) -> bool:
	return mode == "battle" or mode == "holdout"

## Is there a score to reach? Capture the flag alone: last flag standing
## is won by being the team still holding one, not by a total.
static func has_target(mode: String) -> bool:
	return mode == "ctf"

## Is `field` worth showing for this mode?
static func uses(field: String, mode: String) -> bool:
	match field:
		"minutes":
			return has_clock(mode)
		"target":
			return has_target(mode)
		"revive", "drop":
			return has_knockouts(mode)
		_:
			return true

## The round lengths this mode offers.
static func lengths_for(mode: String) -> Array:
	return HoldoutRules.LENGTHS if mode == "holdout" else BATTLE_LENGTHS

# ------------------------------------------------------------------
# Labels
# ------------------------------------------------------------------

static func mode_label(key: String) -> String:
	return _label_in(MODES, "key", key, "Just building")

static func map_label(key: String) -> String:
	return _label_in(MAPS, "key", key, "Island")

static func size_label(value: int) -> String:
	for row: Dictionary in SIZES:
		if int(row["value"]) == value:
			return str(row["label"])
	return "%d across" % value

static func length_label(minutes: int) -> String:
	return "No clock" if minutes >= UNLIMITED else "%d min" % minutes

## "5 computer players", and "Just us" rather than "0 computer players" —
## a zero reads as something failing to load.
static func bots_label(count: int) -> String:
	if count <= 0:
		return "Just us"
	if count == 1:
		return "1 computer player"
	return "%d computer players" % count

static func _label_in(table: Array, key_name: String, wanted: String,
		fallback: String) -> String:
	for row: Dictionary in table:
		if str(row[key_name]) == wanted:
			return str(row["label"])
	return fallback

## ONE LINE SAYING WHAT A GAME IS, for the list on the front page.
##
## It is the whole reason the settings travel back out of the lobby again:
## a list of room names tells you nothing about which one to join, and
## "Capture the flag · Castles" tells you everything. A room that reported
## no settings — an older one, or the always-on world — gets its name and
## nothing invented on top.
static func summary(settings: Dictionary) -> String:
	if settings.is_empty():
		return ""
	var mode := str(settings.get("mode", ""))
	if mode.is_empty():
		return ""
	var parts: Array = [mode_label(mode)]
	var map_key := str(settings.get("map", ""))
	if not map_key.is_empty():
		parts.append(map_label(map_key))
	var size := int(settings.get("size", 0))
	if size > 0:
		parts.append("%d across" % size)
	return " · ".join(parts)

# ------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------

## Whatever came in, made safe. Unknown keys dropped, unknown values
## replaced by the default, numbers snapped to the row they belong to.
##
## SNAPPED, not clamped, for the ones that are a list of choices: a size
## of 137 is not a small world, it is a value nothing on this screen can
## produce, and letting it through means a world nobody chose and a button
## row with nothing highlighted in it.
static func clean(raw: Dictionary) -> Dictionary:
	var out := defaults()
	if _has_key(raw, MODES, "mode"):
		out["mode"] = str(raw["mode"])
	if _has_key(raw, MAPS, "map"):
		out["map"] = str(raw["map"])
	out["size"] = _snap_int(raw, "size", _values_of(SIZES), DEFAULT_SIZE)
	out["bots"] = _snap_int(raw, "bots", BOT_COUNTS, DEFAULT_BOTS)
	out["target"] = _snap_int(raw, "target", TARGETS, DEFAULT_TARGET)
	out["minutes"] = _snap_int(raw, "minutes", lengths_for(str(out["mode"])),
		DEFAULT_MINUTES)
	# The revive ladder is a range rather than a list, so it clamps.
	out["revive"] = clampi(int(raw.get("revive", ReviveRule.MATES_AND_FLAG)),
		ReviveRule.NONE, ReviveRule.MATES_AND_FLAG)
	out["drop"] = bool(raw.get("drop", false))
	return out

static func _values_of(table: Array) -> Array:
	var out: Array = []
	for row: Dictionary in table:
		out.append(int(row["value"]))
	return out

static func _has_key(raw: Dictionary, table: Array, field: String) -> bool:
	if not raw.has(field):
		return false
	var wanted := str(raw[field])
	for row: Dictionary in table:
		if str(row["key"]) == wanted:
			return true
	return false

static func _snap_int(raw: Dictionary, field: String, allowed: Array,
		fallback: int) -> int:
	if not raw.has(field):
		return fallback
	var wanted := int(raw[field])
	return wanted if wanted in allowed else fallback
