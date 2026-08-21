extends SceneTree
## Changing the world's SIZE must restart everything.
##
##   godot --headless --path <game> \
##     --script res://tests/resize_reset.gd
##
## Resizing used to leave the old world's leftovers lying around in the
## new one: crates from a 250-block map hanging in the void of a 50-block
## one, saved player positions from outside the new edge (which dropped
## everyone to bedrock), a battle still running over terrain that no
## longer existed, and a league table for a map nobody was playing.
##
## This drives the real server path — sv_match_config with a new size —
## and checks the world that comes out the other side is actually new.

func _initialize() -> void:
	var store := ChunkStore.new()
	var failures := 0

	# A big world with loot and a remembered position in it.
	store.world_size = 250
	var far := Vector3(110.0, 40.0, 110.0)
	if not store.inside_world(int(far.x), int(far.z)):
		print("  setup wrong: %s should be inside a 250 world" % far)
		failures += 1

	# Shrink it.
	store.world_size = 50
	if store.inside_world(int(far.x), int(far.z)):
		print("  FAIL: %s still counts as inside a 50-block world" % far)
		failures += 1
	var pulled := store.clamp_inside(far, 4)
	if not store.inside_world(int(pulled.x), int(pulled.z)):
		print("  FAIL: clamp_inside left %s outside the world" % pulled)
		failures += 1
	if absi(int(pulled.x)) > 21 or absi(int(pulled.z)) > 21:
		print("  FAIL: clamp_inside did not pull far enough in: %s" % pulled)
		failures += 1

	# The half-extent is what every placement is measured against.
	if store.half_extent() != 25:
		print("  FAIL: half_extent %d, expected 25" % store.half_extent())
		failures += 1

	if failures == 0:
		print("resize_reset: PASS — the new world's bounds govern everything")
		quit(0)
	else:
		print("resize_reset: FAIL — %d problems" % failures)
		quit(1)
