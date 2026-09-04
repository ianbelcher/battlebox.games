class_name EnvConfig
## Every environment variable this project reads, in one place.
##
## The variables are still READ where they are used — a hook only
## `fake_pad.gd` cares about belongs in `fake_pad.gd`, and routing it
## through a singleton would move it away from its own explanation. What
## lives here is the REGISTRY: one documented list, and typed readers so
## the same "is it a valid int, and what if it is not" dance is not
## written sixty times with sixty slightly different answers.
##
## `tests/unit/env_config_test.gd` scans src/ and tests/ for
## `OS.get_environment(...)` and fails on any name that is not in the
## table below. That is what stops this list from drifting into fiction:
## adding a hook without documenting it breaks the build on the day it is
## added, rather than leaving the next person to grep for it.

## name -> what it does. The comment IS the documentation; there is
## nowhere else that lists these.
const KNOWN := {
	# --- What a server is ---------------------------------------------
	"WORLD_ROLE": "server | client. Headless implies server unless this says otherwise",
	"WORLD_NETSTAT": "1 reports how many position packets a second the server sends",
	"WORLD_PORT": "port the game socket listens on (default 9081)",
	"WORLD_SOURCE": "procedural | mca — where terrain comes from",
	"WORLD_SEED": "procedural seed (default 20260726)",
	"WORLD_THEME": "procedural theme (default classic)",
	"WORLD_SIZE": "side of the square world, in blocks (default 250)",
	"WORLD_MCA_DIR": "a Minecraft world directory, or its region/ directory",
	"WORLD_MCA_Y0": "the Minecraft y that becomes world floor + 1 (default 40)",
	"WORLD_MCA_CENTER": "the Minecraft x,z that becomes our origin, chunk-aligned",
	"WORLD_CLIMB_TEST": "walk into a wall this many blocks high and see if you get over",
	"WORLD_CLOCK": "pin the day fraction, 0..1, so a given hour can be looked at",
	"WORLD_FAST": "1 shrinks the day to 90s and sapling growth to 8s",

	# --- What a room was ASKED to be -------------------------------------
	#
	# Chosen on the front page before the room exists, carried here by the
	# lobby (see lobby/lobby.py's settings_env) and applied at boot. A
	# world is generated from its environment and never written to disk,
	# so this is the difference between a room that IS a desert and a room
	# that resets itself into one while somebody is standing in it.
	"WORLD_MODE": "creative | battle | ctf | holdout — the mode a room starts in",
	"WORLD_ROUND_MINUTES": "how long a round of battle royale or last flag standing runs",
	"WORLD_BOTS": "computer players waiting in the world at boot",
	"WORLD_CTF_TARGET": "captures needed to win capture the flag",
	"WORLD_TEAMS": "how many sides the game is played across",
	"WORLD_FLY": "everyone | nobody | computers | humans — who may fly",
	"WORLD_REVIVE": "0 nobody · 1 team-mates · 2 team-mates and your own flag",
	"WORLD_DROP_KO": "1 drops your weapons where you fell",

	# --- Rooms ---------------------------------------------------------
	"WORLD_ROOM_CODE": "this room's join code; absent means the always-on game",
	"WORLD_ROOM_NAME": "what the creator called this room",
	"WORLD_ROOM_PUBLIC": "1 to be listed on the front page",
	"WORLD_IDLE_EXIT": "seconds alone before the room closes itself; 0 never",

	# --- What a client dials --------------------------------------------
	"WORLD_SERVER_URL": "the machine to dial; beats the saved address",
	"WORLD_ROOM": "join this room code on launch, skipping the lobby screen",
	"WORLD_AUTOCONNECT": "a whole socket address, bypassing the lobby entirely",

	# --- Video ------------------------------------------------------------
	"WORLD_MAXFX": "1 adds SDFGI bounce light (never volumetric fog — see daynight.gd)",

	# --- Driving the game without a person ---------------------------------
	"WORLD_AUTOTEST": "join n bot players who wander, dig and build",
	"WORLD_AUTOTEST_HUMAN": "1 makes the first seat a plain keyboard slot",
	"WORLD_AUTOTEST_WHO": "pin each seat's character, comma-separated",
	"WORLD_AUTOTEST_NAME": "type a name through the HUD, as a player would",
	"WORLD_AUTOTEST_PICK": "drive the block picker's UI",
	"WORLD_AUTOTEST_TAB": "leave the menu open on this tab",
	"WORLD_AUTOTEST_MENU": "1 opens the menu on its own",
	"WORLD_AUTOTEST_BLOCK": "pin every bot's hotbar to one block id",
	"WORLD_AUTOTEST_SERVER_BOTS": "ask the server for n computer players",
	"WORLD_AUTOTEST_MODE": "creative | battle | ctf | holdout, chosen before the round",
	"WORLD_HOLDOUT_MINUTES": "shorten last flag standing so a round can be watched end to end",
	"WORLD_AUTOTEST_MATCH": "start n rounds",
	"WORLD_AUTOTEST_SURVIVAL": "1 starts a Grump raid",
	"WORLD_FAKE_PADS": "pretend n gamepads are plugged in",
	"WORLD_FAKE_PAD_HOLD": "lb | rb — pretend that shoulder button is held",

	# --- Reporting and probes -----------------------------------------------
	"WORLD_SELFCHECK": "seconds before printing a SELFCHECK state line",
	"WORLD_SELFCHECK_REPEAT": "1 keeps reporting and does not quit (servers)",
	"WORLD_SHOTS": "directory; save a screenshot every 1.5s",
	"WORLD_SHOWCASE": "1 plants a strip of every foliage block near spawn",
	"WORLD_REVIVE_TEST": "1 downs a computer player, stands a team-mate on it and reports the pick-up",
	"WORLD_RESIZE_TEST": "resize the world to this mid-session, then check nobody fell off",
	"WORLD_WIN_TEST": "hand out knockouts and end the round for this team",
	"WORLD_KICK_TEST": "1 kicks a player and checks they are forgotten",
	"WORLD_SMOKE_TEST": "1 fires a smoke round at the world",
	"WORLD_MENU_TEST": "1 opens the world menu on its own",
	"WORLD_MENU_TAB": "leave the world menu on this tab",
	"WORLD_MENU_PROBE": "1 drives the world menu with synthetic input",
	"WORLD_LOBBY_SCREEN": "new | code — open one of the front page's other screens at boot",
	"WORLD_BOT_PIT_TEST": "drop the bots into holes this deep, to exercise digging out",
	"WORLD_BOT_WEAPON": "give every bot this weapon id at the drop",
	"WORLD_TEST_FILTER": "run only unit tests whose name contains this",

	# --- Logging --------------------------------------------------------------
	"WORLD_DEBUG": "1 logs player physics state",
	"WORLD_BOAT_TEST": "1 stands a player on a boat and moves it under them",
	"WORLD_DOWNED_TINTS": "1 knocks this player out and reports every red overlay's alpha",
	"WORLD_KNOCKOUT_TEST": "seconds into a battle to knock the human down, through the real damage path",
	"WORLD_KNOCKOUT_NOFLY": "1 switches flying off first, to check a revive takes the wings back",
	"WORLD_KNOCKOUT_NOREVIVE": "1 switches reviving off first, to check a knockout is final",
	"WORLD_SWITCH_TEST": "a theme to switch to mid-round, checking the ground really changes",
	"WORLD_CAPTURE_TEST": "1 stands the person on an enemy flag to see if touching it takes it",
	"WORLD_ROUNDCLOCK_TEST": "1 checks the round clock runs at one second per second",
	"WORLD_ROOF_TEST": "1 counts the wall and roof blocks defenders put up around each flag",
	"WORLD_HOLDOUT_SET": "minutes to set the last-flag round length to, through the real setter",
	"WORLD_HUDDLE_TEST": "1 counts who is sat on their own flag and who is out attacking",
	"WORLD_POLE_TEST": "1 turns reviving off and checks no flag channel starts with no way back",
	"WORLD_GHOST_TEST": "1 reports whether a knocked-out team is actually hidden, or drawn and moving",
	"WORLD_SIGHT_TEST": "1 reports which seats the names and hearts over each head are drawn for",
	"WORLD_SIEGE_TEST": "1 reports how close anybody actually gets to an enemy flag, against the touch radius",
	"WORLD_SNIPE_TEST": "1 shoots a computer player from out of its sight and reports its reaction",
	"WORLD_SPREAD_TEST": "1 reports how far apart a team's defenders stand and which sides they cover",
	"WORLD_BOT_DEBUG": "1 logs what the computer players are deciding",
	"WORLD_ORB_DEBUG": "1 logs every bot shot's flight",
	"WORLD_FLIER_DEBUG": "1 logs flying critters' altitude decisions",
	"WORLD_VIDEO_DEBUG": "1 logs the video settings actually in force",

	# --- Offline generators (tests/, run by hand) --------------------------------
	"WORLD_MAP_OUT": "where to write a top-down map render",
	"WORLD_MAP_THEME": "which procedural theme to render",
	"WORLD_MAP_SPAN": "how many chunks across to render",
	"WORLD_MAP_ZOOM": "pixels per block in the render",
	"WORLD_MAP_SIZE": "world size to generate before rendering",
	"WORLD_ICON_IDS": "weapon ids to render hotbar icons for",
	"WORLD_ICON_OUT": "where to write those icons",
	"WORLD_NBT_DIR": "directory of Minecraft .nbt/.schem files to import",
	"WORLD_NBT_OUT": "where to write the generated kit file",
	"WORLD_NBT_MANIFEST": "kits/manifest.json, for per-build names and authors",
	"WORLD_NBT_BY": "fallback author for builds the manifest does not name",
	"WORLD_NBT_LICENSE": "licence to record for the imported builds",
	"WORLD_NBT_SOURCE": "URL to record as where they came from",
	"WORLD_NBT_ALL": "1 imports everything found rather than a curated list",
}

## Set, and not empty. The distinction matters: an unset variable and one
## set to "" both mean "not asked for", and Godot returns "" for both.
static func has(key: String) -> bool:
	return not OS.get_environment(key).strip_edges().is_empty()

static func text(key: String, fallback := "") -> String:
	var value := OS.get_environment(key).strip_edges()
	return value if not value.is_empty() else fallback

## True only for "1". Not "true", not "yes", not any non-empty string — one
## spelling, so WORLD_FAST=0 means off rather than accidentally on.
static func flag(key: String) -> bool:
	return OS.get_environment(key).strip_edges() == "1"

static func number(key: String, fallback: int) -> int:
	var value := OS.get_environment(key).strip_edges()
	return value.to_int() if value.is_valid_int() else fallback

static func decimal(key: String, fallback: float) -> float:
	var value := OS.get_environment(key).strip_edges()
	return value.to_float() if value.is_valid_float() else fallback

## The registry as a sorted list, for the docs and for the test.
static func names() -> Array:
	var out: Array = KNOWN.keys()
	out.sort()
	return out
