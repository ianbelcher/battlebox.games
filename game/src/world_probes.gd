class_name WorldProbes
extends Node
## Dev-only scaffolding: the WORLD_*_TEST hooks that drive the server
## through a scenario on a timer so a headless run can prove something
## that would otherwise need four children and two controllers.
##
## Kept out of world.gd because none of it is the game. Each probe is
## inert unless its environment variable is set, so this node costs one
## `is_valid_int()` per tick in a real server and nothing else.
##
##   WORLD_RESIZE_TEST=<size>   resize mid-session, then check nobody fell
##                              off the map
##   WORLD_WIN_TEST=<team>      hand out knockouts and end the round
##   WORLD_KICK_TEST=1          kick a player and check they are forgotten
##   WORLD_SMOKE_TEST=1         fire a smoke round at the world
##   WORLD_BOTWATCH=1           report computer players that stopped moving

## The world being probed.
var world: WorldNode = null


## Boom blocks explode after their fuse; fireworks launch. Both checked
## every frame (the lists are tiny).
## The smoke marker times out by itself, so a match that runs long isn't
## still being pointed at a building somebody took ten minutes ago.
## WORLD_RESIZE_TEST=<size>: resize the world after 12s, then report
## every player's position for the next 12s and whether it is on the map.
## This is the exact sequence that kept stranding people — a running
## world with computer players in it, shrunk under them — and it is the
## only way to check it end to end without a person driving the menu.
var _resize_t := 0.0
var _resize_done := false
## WORLD_KICK_TEST=1: kick the first human after 15s. Proves that the ✕
## in the world menu actually gives up that player's SEAT on their own
## machine — the split screen drops to fewer cells, and if they were the
## last one there the join prompt comes back.
var _kick_t := 0.0
var _kick_done := false
## WORLD_WIN_TEST=<team>: hand a few knockouts around, then end the
## battle for that team after 22s. Checks the end-of-match scoreboard
## renders, and that ONE win is recorded for one game — the banner used
## to say two.
var _win_t := 0.0
var _win_done := false
## WORLD_BOT_DEBUG=1: every ten seconds, report how far each computer
## player actually got. "Stuck" is the failure that matters — a bot
## standing in a hole turning on the spot — and it is invisible in a
## screenshot, so it needs a number.
var _watch_t := 0.0
var _watch_from: Dictionary = {}
## WORLD_SMOKE_TEST=1: throw a smoke bomb every second, forever. Each one
## takes the last one down, which is exactly the path that used to strand
## a dozen infinite tweens per bomb on every client and grind them to a
## halt after a few throws.
var _smoke_t := 0.0

func tick_resize(delta: float) -> void:
	var want := OS.get_environment("WORLD_RESIZE_TEST")
	if not want.is_valid_int():
		return
	_resize_t += delta
	# Bring some computer players along: they are the case that broke,
	# and relying on a client to add them made the run flaky.
	if _resize_t > 6.0 and world.bots.roster.size() < 4:
		world.bots.spawn()
	if not _resize_done and _resize_t > 12.0:
		_resize_done = true
		print("RESIZETEST resizing to %s" % want)
		world.sv_match_config(-1, -1, want.to_int(), -1)
	if _resize_done and fmod(_resize_t, 3.0) < delta:
		var half := world.store.half_extent()
		var bad := 0
		for id: String in world.player_state.keys():
			var at: Vector3 = world.player_state[id].pos
			var inside := world.store.inside_world(floori(at.x), floori(at.z), 0)
			if not inside:
				bad += 1
			print("RESIZETEST %s %s at (%d,%d) half=%d %s" % [
				str(Game.roster.get(id, {}).get("name", "?")),
				"bot" if world.bots.roster.has(id) else "human",
				floori(at.x), floori(at.z), half,
				"OK" if inside else "*** OFF THE MAP ***"])
		print("RESIZETEST %d of %d off the map" % [bad, world.player_state.size()])
func tick_win(delta: float) -> void:
	var want := OS.get_environment("WORLD_WIN_TEST")
	if not want.is_valid_int() or _win_done:
		return
	_win_t += delta
	if _win_t < 22.0 or world.match_phase != "BATTLE":
		return
	_win_done = true
	# Some knockouts to fill the table with, credited across teams.
	var ids: Array = Game.roster.keys()
	for i in mini(ids.size(), 6):
		var attacker: String = ids[i]
		var victim: String = ids[(i + 3) % ids.size()]
		if world.teams_differ(attacker, victim):
			world.battle.credit_frag(attacker)
	world.battle.broadcast_scoreboard()
	print("WINTEST ending for team %s, frags=%s" % [want, str(world.player_frags)])
	world.battle.finish(want.to_int())
	print("WINTEST wins now %s (should be exactly one for team %s)"
		% [str(world.team_wins), want])
func tick_kick(delta: float) -> void:
	if OS.get_environment("WORLD_KICK_TEST") != "1":
		return
	_kick_t += delta
	if _kick_done or _kick_t < 15.0:
		return
	for id: String in Game.roster.keys():
		if bool(Game.roster[id].get("bot", false)):
			continue
		_kick_done = true
		print("KICKTEST kicking %s (%s)" % [
			str(Game.roster[id].get("name", "?")), id])
		Game.sv_kick_player(id)
		return
func tick_smoke(delta: float) -> void:
	if OS.get_environment("WORLD_SMOKE_TEST") != "1":
		return
	_smoke_t += delta
	if _smoke_t < 1.0:
		return
	_smoke_t = 0.0
	var at := world.store.safe_stand(Vector3(world.spawn_pos), 12.0)
	world._smoke_marker = {"pos": at, "team": randi() % 4,
		"until": Time.get_ticks_msec() + world.SMOKE_MSEC}
	world.cl_smoke.rpc(at, int(world._smoke_marker.team))
func tick_bot_watch(delta: float) -> void:
	if OS.get_environment("WORLD_BOT_DEBUG") != "1":
		return
	_watch_t += delta
	if _watch_t < 10.0:
		return
	_watch_t = 0.0
	var stuck := 0
	var moved_total := 0.0
	var counted := 0
	for id: String in world.bots.roster.keys():
		# Only ones that are actually trying to go somewhere. A bot that
		# is out of the match, or lying downed, has every right not to
		# have moved, and counting it made the number meaningless.
		if world.match_phase == "BATTLE" and (not world.match_alive.has(id)
				or world.downed_ids.has(id)):
			continue
		if world.match_phase != "BATTLE" and world.match_phase != "IDLE":
			continue
		counted += 1
		var at: Vector3 = world.bots.roster[id].pos
		var was: Vector3 = _watch_from.get(id, at)
		var gone := Vector2(at.x - was.x, at.z - was.z).length()
		moved_total += gone
		if gone < 2.0:
			stuck += 1
			print("BOTWATCH %s STUCK at (%d,%d,%d), moved %.1f in 10s" % [
				str(Game.roster.get(id, {}).get("name", "?")),
				floori(at.x), floori(at.y), floori(at.z), gone])
		_watch_from[id] = at
	if counted > 0:
		print("BOTWATCH %d/%d stuck, average %.1f blocks in 10s" % [
			stuck, counted, moved_total / float(counted)])


## Every probe, once per frame. They are all inert without their
## environment variable, so this is five integer checks on a real server.
func tick(delta: float) -> void:
	tick_resize(delta)
	tick_kick(delta)
	tick_win(delta)
	tick_bot_watch(delta)
	tick_smoke(delta)
