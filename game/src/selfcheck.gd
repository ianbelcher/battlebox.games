class_name SelfCheck
extends Node
## A machine-readable snapshot of what this process actually ended up
## with, printed once and then the process quits.
##
##   WORLD_SELFCHECK=<seconds>   how long to run before reporting
##   WORLD_SELFCHECK_REPEAT=1    keep reporting every <seconds> and stay up
##
## A client reports once and quits. A server is asked to REPEAT, because
## the thing worth measuring about a server is its state while somebody is
## connected to it — a server that reported after the last client left
## would truthfully say it has nobody in it.
##
## This exists because "it started and did not crash" proves almost
## nothing about this game: the server can serve, the client can connect,
## the socket can be up, and the world can still be empty because an RPC
## went to a node path that no longer exists. Godot does not raise on
## that — the call simply lands nowhere.
##
## So the check is on the STATE both ends reached, not on the absence of
## errors. tools/integration_test.py runs a server and a client under it
## and fails the build if either line comes back short.

## Printed in front of the report so a log scraper can find it.
const TAG := "SELFCHECK"

var _seconds := 0.0
var _elapsed := 0.0
var _repeat := false

static func wanted() -> float:
	return EnvConfig.decimal("WORLD_SELFCHECK", 0.0)

func _init(seconds: float) -> void:
	_seconds = seconds
	_repeat = EnvConfig.flag("WORLD_SELFCHECK_REPEAT")

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < _seconds:
		return
	_elapsed = 0.0
	print("%s %s" % [TAG, " ".join(_report())])
	if not _repeat:
		set_process(false)
		get_tree().quit(0)

## PlayerHud instances under the split screen, counted by class rather
## than by node path so a re-layout does not silently zero it.
func _huds_built() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("player_hud"):
		if is_instance_valid(node):
			count += 1
	return count

## Which control the keyboard and the gamepad are currently pointed at.
##
## Reported because the one-press path is otherwise unverifiable without a
## person looking at a screenshot and judging a stylebox. It is not a
## detail: if nothing holds focus, Space and Ⓐ do nothing at all, and if
## the WRONG thing holds it they do something nobody asked for. Both have
## happened here, and neither logged a thing.
func _focused() -> String:
	var vp := get_viewport()
	if vp == null:
		return "-"
	var owner := vp.gui_get_focus_owner()
	if owner == null:
		return "none"
	# The text, when there is any, because that is what a person reading
	# the line is trying to confirm — "Play", not "@Button@37".
	if owner is Button and not (owner as Button).text.strip_edges().is_empty():
		return (owner as Button).text.strip_edges().replace(" ", "_")
	return owner.name

func _report() -> Array[String]:
	var world: WorldNode = Game.world
	var fields: Array[String] = []
	fields.append("role=%s" % ("server" if Net.is_server else "client"))
	if not Net.is_server:
		var shell := get_parent() as Main
		fields.append("screen=%s" % (shell.current_screen() if shell != null else "?"))
		fields.append("focus=%s" % _focused())
		fields.append("room=%s" % (Game.joined_code if not Game.joined_code.is_empty()
			else "-"))
	if world == null:
		fields.append("world=none")
		return fields
	fields.append("peers=%d" % multiplayer.get_peers().size())
	fields.append("roster=%d" % Game.roster.size())
	fields.append("clock=%.3f" % float(world.clock))
	fields.append("mode=%s" % str(world.game_mode if Net.is_server else world.client_mode))
	fields.append("phase=%s" % str(world.match_phase))
	fields.append("alive=%d" % world.match_alive.size())
	fields.append("spawn=%d,%d,%d" % [world.spawn_pos.x, world.spawn_pos.y,
		world.spawn_pos.z])
	if Net.is_server:
		fields.append("chunks=%d" % world.store.cached_count())
		fields.append("critters=%d" % world.critters_sim.count())
		fields.append("edits=%d" % world.store.edited_count())
		fields.append("bots=%d" % world.bots.roster.size())
	else:
		fields.append("chunks=%d" % world.chunks.loaded_count())
		fields.append("critters=%d" % world.critter_view.count())
		fields.append("avatars=%d" % world.players.get_child_count())
		# How many per-player HUDs were actually BUILT. A headless run
		# constructs the whole interface — every panel, every menu page —
		# so this is what proves a UI refactor did not quietly stop it.
		fields.append("huds=%d" % _huds_built())
	return fields
