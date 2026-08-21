class_name Room
extends Node
## What this server process IS: one game room, and the watchdog that ends
## it when the last person leaves.
##
## A room is a whole server process, not a compartment inside one. The
## lobby (see lobby/) starts one per game and proxies players to it. That
## costs a process, and buys three things worth more than the process:
##
##   - a room that crashes takes only its own players with it
##   - rooms run on different cores, and this server's per-frame work
##     (bots, water, fire, critters) is all on one thread
##   - a room that ends is a process that exits, so there is no cleanup
##     path to get wrong and no memory to leak between games
##
## The world itself did not have to change at all to be a room: it was
## already configured entirely from the environment and already wrote
## nothing to disk.
##
##   WORLD_ROOM_CODE    the adjective-noun handle players join with
##   WORLD_ROOM_NAME    what the creator called it
##   WORLD_ROOM_PUBLIC  1 to be listed on the front page
##   WORLD_IDLE_EXIT    seconds alone before quitting; 0 never quits

## The always-on public game has no code and never exits. Every other room
## is created on demand and reaped.
const HOUSE_CODE := "house"

## Checked this often rather than every frame; a room ending a few hundred
## milliseconds late costs nothing.
const POLL_SECONDS := 2.0

var code := HOUSE_CODE
var display_name := "BattleBox"
var is_public := true
## Seconds with nobody connected before this process quits. Zero means
## never, which is what the house room runs with.
var idle_exit_seconds := 0.0

var _alone_for := 0.0
var _poll := 0.0
## Last count printed, so the heartbeat is one line per CHANGE rather than
## one line every two seconds forever in the lobby's log.
var _said_players := -1
## True once somebody has connected. A room that nobody EVER joined still
## has to go away — the lobby starts it optimistically when a player asks
## for one, and if they never arrive it would otherwise sit there forever.
var _ever_joined := false

func _init() -> void:
	code = EnvConfig.text("WORLD_ROOM_CODE", HOUSE_CODE)
	display_name = EnvConfig.text("WORLD_ROOM_NAME", "BattleBox")
	is_public = EnvConfig.text("WORLD_ROOM_PUBLIC", "1") == "1"
	idle_exit_seconds = maxf(0.0, EnvConfig.decimal("WORLD_IDLE_EXIT", 0.0))

func is_house() -> bool:
	return code == HOUSE_CODE

## One line the lobby can read off this process's stdout to know what it
## started. Printed once at boot, before anyone can connect.
func describe() -> String:
	return "ROOM code=%s name=%s public=%s idle_exit=%.0f" % [
		code, display_name, "1" if is_public else "0", idle_exit_seconds]

## How many people are in this room, on the room's stdout, whenever it
## changes. The lobby reads this to show "3 playing" beside a public game;
## it cannot count sockets instead, because one machine's socket can carry
## up to four players sharing a screen.
func _report_players() -> void:
	var count := Game.roster.size()
	if count == _said_players:
		return
	_said_players = count
	print("ROOM %s players=%d" % [code, count])

func _process(delta: float) -> void:
	_poll += delta
	if _poll < POLL_SECONDS:
		return
	_poll = 0.0
	_report_players()
	if idle_exit_seconds <= 0.0:
		return          # the house room never closes
	var peers := multiplayer.get_peers().size()
	if peers > 0:
		_ever_joined = true
		_alone_for = 0.0
		return
	_alone_for += POLL_SECONDS
	if _alone_for < idle_exit_seconds:
		return
	# A world that is only in memory has nothing to write out, so ending is
	# just stopping. Say why, because "the room disappeared" is otherwise
	# indistinguishable from a crash in the lobby's logs.
	print("ROOM %s: %s for %.0fs, closing" % [code,
		"empty" if _ever_joined else "never joined", _alone_for])
	get_tree().quit(0)
