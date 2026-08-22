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
## No autoloads, no scene tree, nothing but integers, so
## tests/unit/split_screen_test.gd can check the arithmetic directly.

## Everything that is not a player: terrain, critters, orbs, the sky.
const WORLD := 1
## Up to four seats.
const SEATS := 4

## A seat's own body — the avatar its player is inside.
static func body_of(slot: int) -> int:
	return 1 << (1 + slot)

## A seat's viewmodel: the held item drawn on that seat's own camera only.
## Seeing somebody else's would hang a second gun in the middle of your view.
static func viewmodel_of(slot: int) -> int:
	return 1 << (10 + slot)

## What one seat's camera may draw. `slot` below zero is the spectator
## camera, which belongs to nobody: it sees every body and no viewmodel.
static func camera_mask(slot: int) -> int:
	var every_viewmodel := 0
	for i in SEATS:
		every_viewmodel |= viewmodel_of(i)
	var mask := ((1 << 20) - 1) & ~every_viewmodel
	if slot < 0:
		return mask
	return (mask & ~body_of(slot)) | viewmodel_of(slot)
