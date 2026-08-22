extends TestCase
## Who each seat's camera can see.
##
## This is the arithmetic behind two people playing on one screen, and it
## failed silently for a long time: your own body was hidden from your own
## first-person camera with `avatar.visible = false`, which is a property
## of the NODE, not of a camera — so it hid you from the player sitting
## next to you as well. Nothing errored. The game ran. You just could not
## see each other.

func test_you_never_see_your_own_body() -> void:
	for slot in 4:
		var mask := RenderLayers.camera_mask(slot)
		var own_body := RenderLayers.body_of(slot)
		equal(mask & own_body, 0,
			"seat %d's camera must not draw seat %d's own body" % [slot, slot])

func test_you_always_see_everybody_else() -> void:
	# The one that matters on a sofa.
	for slot in 4:
		var mask := RenderLayers.camera_mask(slot)
		for other in 4:
			if other == slot:
				continue
			var their_body := RenderLayers.body_of(other)
			not_equal(mask & their_body, 0,
				"seat %d's camera MUST draw seat %d" % [slot, other])

func test_you_see_your_own_held_item_and_nobody_elses() -> void:
	# The viewmodel is the weapon drawn on your own camera. Seeing
	# somebody else's would put a floating gun in the middle of your view.
	for slot in 4:
		var mask := RenderLayers.camera_mask(slot)
		not_equal(mask & (RenderLayers.viewmodel_of(slot)), 0,
			"seat %d sees its own viewmodel" % slot)
		for other in 4:
			if other == slot:
				continue
			equal(mask & (RenderLayers.viewmodel_of(other)), 0,
				"seat %d must not see seat %d's viewmodel" % [slot, other])

func test_the_world_itself_is_always_drawn() -> void:
	# Layer 1 is everything that is not a player: terrain, critters, orbs.
	for slot in [-1, 0, 1, 2, 3]:
		not_equal(RenderLayers.camera_mask(slot) & RenderLayers.WORLD, 0,
			"seat %d draws the world" % slot)

func test_the_spectator_camera_sees_every_body_and_no_viewmodel() -> void:
	var mask := RenderLayers.camera_mask(-1)
	for slot in 4:
		not_equal(mask & (RenderLayers.body_of(slot)), 0,
			"the spectator sees seat %d" % slot)
		equal(mask & (RenderLayers.viewmodel_of(slot)), 0,
			"the spectator sees no held item for seat %d" % slot)
