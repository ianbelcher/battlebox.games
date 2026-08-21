extends SceneTree
## Regenerating the world must MOVE THE COMPUTER PLAYERS.
##
##   godot --headless --path <game> \
##     --script res://tests/reset_bots.gd
##
## Reported, exactly: "Alpha and Bravo were both placed outside the
## map. I then regenerated and found that they both were placed in the
## same position again outside the map."
##
## The cause was that a computer player's position lives in WorldNode's
## `_bots` dictionary, which is not `_player_state` — and the world reset
## cleared the latter and never touched the former. So a bot stood
## wherever it had been standing in the world before, which on a smaller
## map is off the edge of it, and regenerating changed nothing because
## nothing was re-rolling their positions at all.
##
## This drives the real thing: place bots far outside a small world, run
## the same repositioning the reset runs, and check they are (a) back on
## the map and (b) NOT where they were.

const SIZE := 50

var _failures := 0

func _initialize() -> void:
	var store := ChunkStore.new()
	store.world_size = SIZE
	store.gen = WorldGen.new(20260726, "classic", SIZE)
	var spawn := store.find_spawn()

	# Two computer players stranded far outside a 50-block world, exactly
	# as a resize from 250 would leave them.
	var bots := {
		"Alpha": {"pos": Vector3(118.0, 40.0, -96.0)},
		"Bravo": {"pos": Vector3(-131.0, 40.0, 77.0)},
	}
	var before := {}
	for who: String in bots:
		before[who] = bots[who].pos
		_expect(not store.inside_world(floori(bots[who].pos.x),
				floori(bots[who].pos.z), 2),
			"setup wrong: %s should start outside a %d world" % [who, SIZE])

	# What _do_world_reset() now does to every bot.
	for who: String in bots:
		bots[who].pos = store.safe_stand(Vector3(spawn), 10.0)

	var seen := {}
	for who: String in bots:
		var at: Vector3 = bots[who].pos
		_expect(store.inside_world(floori(at.x), floori(at.z), 2),
			"%s still outside the world at %s" % [who, at])
		_expect(at != before[who],
			"%s did not move: still at %s" % [who, at])
		var under := store.get_block(Vector3i(floori(at.x), floori(at.y) - 1,
			floori(at.z)))
		_expect(under != Blocks.AIR,
			"%s is standing on air at %s" % [who, at])
		# Not stacked on top of each other either.
		var key := "%d,%d" % [floori(at.x), floori(at.z)]
		_expect(not seen.has(key), "%s landed on the same block as another" % who)
		seen[key] = true

	# And doing it again gives DIFFERENT spots — "regenerated and they
	# were placed in the same position again" is the actual complaint.
	var moved_again := false
	for attempt in 8:
		var again := store.safe_stand(Vector3(spawn), 10.0)
		if again != bots["Alpha"].pos:
			moved_again = true
			break
	_expect(moved_again, "repositioning is deterministic — a regenerate "
		+ "would put everyone back in the same spot")

	if _failures == 0:
		print("reset_bots: PASS — a regenerate moves the computer players "
			+ "somewhere new, on the map")
		quit(0)
	else:
		print("reset_bots: FAIL — %d problems" % _failures)
		quit(1)

func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	print("  " + message)
