class_name RenderLayers
## Which camera draws what, on a split screen.
##
## Godot gives every VisualInstance3D a layer mask and every Camera3D a
## cull mask, and draws a thing only where the two overlap. That is the
## whole mechanism behind four people sharing one screen: everybody is in
## the same World3D, and each seat's camera simply declines to draw the
## body it is sitting inside.
##
## THIS IS WHY IT IS CULLING AND NOT `avatar.visible = false`. `visible`
## belongs to the node, not to a camera: hiding your body from yourself
## that way hides it from the person next to you too, and two players on
## one sofa cannot see each other. That shipped, and nothing caught it —
## the game runs perfectly, you are just alone in it.
##
## The same trick carries the name and hearts over a player's head, which
## are the one thing that should NOT be drawn everywhere: somebody hiding
## behind a wall is given away by their hearts floating over it. So each
## seat has its own overhead layer, and a tag is put on a seat's layer
## only while that seat's camera can actually see the body under it (see
## OverheadSight and SplitScreen._update_overhead_sight).
##
## No autoloads, no scene tree, nothing but integers, so
## tests/unit/split_screen_test.gd can check the arithmetic directly.

## Everything that is not a player: terrain, critters, orbs, the sky.
const WORLD := 1
## Up to four seats.
const SEATS := 4

## A seat's own body — the avatar its player is inside.
static func body_of(slot: int) -> int:
	return 1 << (1 + slot)

## The overhead tags (name, hearts) that one seat can see right now.
static func overhead_of(slot: int) -> int:
	return 1 << (5 + slot)

## The overhead tags as the spectator camera sees them: all of them, all
## the time. It belongs to nobody and is nobody's opponent, so there is
## nothing to give away.
const OVERHEAD_SPECTATOR := 1 << 9

static func every_overhead() -> int:
	var mask := OVERHEAD_SPECTATOR
	for i in SEATS:
		mask |= overhead_of(i)
	return mask

## A seat's viewmodel: the held item drawn on that seat's own camera only.
## Seeing somebody else's would hang a second gun in the middle of your view.
static func viewmodel_of(slot: int) -> int:
	return 1 << (10 + slot)

## What one seat's first-person camera may draw. `slot` below zero is the
## spectator camera, which belongs to nobody: it sees every body, every
## overhead tag, and no viewmodel.
static func camera_mask(slot: int) -> int:
	var every_viewmodel := 0
	for i in SEATS:
		every_viewmodel |= viewmodel_of(i)
	var mask := ((1 << 20) - 1) & ~every_viewmodel & ~every_overhead()
	if slot < 0:
		return mask | OVERHEAD_SPECTATOR
	return (mask & ~body_of(slot)) | viewmodel_of(slot) | overhead_of(slot)

## The same seat looking at itself from outside (the orbit and map views):
## its own body is in the picture and no gun hangs in front of it, so this
## is the spectator's view — EXCEPT for the tags. The orbit view used to
## borrow the spectator mask whole, and with it the always-on overhead
## layer, so a seat in third person saw every tag on the map and a row of
## hearts over its own head.
static func orbit_mask(slot: int) -> int:
	return (camera_mask(-1) & ~OVERHEAD_SPECTATOR) | overhead_of(slot)
