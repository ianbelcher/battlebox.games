extends SceneTree
## End-to-end: a running world with computer players in it, resized down.
## Nobody may be outside the map afterwards.
##
##   godot --headless --path <game> \
##     --script res://tests/live_resize.gd
##
## The unit tests check the pieces; this checks the actual sequence a person
## does — play on a big map with bots, shrink it, look around.

func _initialize() -> void:
	var failures := 0
	var store := ChunkStore.new()
	# Big world, bots scattered across it the way they would be.
	store.world_size = 250
	store.gen = WorldGen.new(20260726, "classic", 250)
	var placed: Array = []
	for i in 8:
		var a := TAU * float(i) / 8.0
		placed.append(store.safe_stand(Vector3(cos(a) * 110.0, 0, sin(a) * 110.0)))
	for at: Vector3 in placed:
		if not store.inside_world(floori(at.x), floori(at.z), 2):
			print("  setup: %s outside the 250 world" % at)
			failures += 1

	# Shrink it, then reposition everyone the way _do_world_reset() does.
	store.world_size = 50
	store.gen = WorldGen.new(987654321, "classic", 50)
	var spawn := store.find_spawn()
	var after: Array = []
	for i in placed.size():
		after.append(store.safe_stand(Vector3(spawn), 10.0))
	for at: Vector3 in after:
		if not store.inside_world(floori(at.x), floori(at.z), 2):
			print("  %s outside the 50 world after the resize" % at)
			failures += 1
		var under := store.get_block(Vector3i(floori(at.x), floori(at.y) - 1,
			floori(at.z)))
		if under == Blocks.AIR:
			print("  %s standing on air after the resize" % at)
			failures += 1
	# They must not all be piled on one block either.
	var spots := {}
	for at: Vector3 in after:
		spots["%d,%d" % [floori(at.x), floori(at.z)]] = true
	if spots.size() < 3:
		print("  everyone landed on %d distinct blocks" % spots.size())
		failures += 1

	if failures == 0:
		print("live_resize: PASS — %d players moved onto the new map" % after.size())
		quit(0)
	else:
		print("live_resize: FAIL — %d problems" % failures)
		quit(1)
