class_name OverheadSight
## Whether a seat can see the player under an overhead tag.
##
## The hearts (and now the name) over a player's head float above the
## blocks they are hiding behind, so anyone crouched in a doorway was
## announced by a row of hearts hovering over the roof. The fix is not to
## hide the tag behind terrain — a tag that clips into a wall is worse —
## but to ask, for each seat on the screen, whether that seat's camera has
## a clear line to the BODY, and only draw the tag on the seats that do.
##
## Cheap on purpose: a straight walk in half-block steps through the
## client's own copy of the world, run a few times a second rather than
## every frame. Twenty players and four seats come to a few thousand block
## reads a pass, which is nothing next to meshing a chunk.
##
## Nothing here touches a node: cameras are passed in as a position and a
## forward vector, and the world as a callable, so tests/unit can drive
## it with a dictionary of blocks.

## How far apart the samples are along the line, in blocks.
const STEP := 0.5

## Two points on the body, so a head poking over a parapet or a pair of
## legs under a fence both count as "I can see them".
const BODY_POINTS: Array[float] = [1.5, 0.6]

## The point a camera's ray actually starts from for a given target.
##
## A perspective camera looks out from one point, so that is the origin.
## An orthographic camera (the orbit and map views) is a plane: every
## pixel's ray runs parallel to the view direction, and the one that
## lands on the target starts where the target projects back onto that
## plane. Using the camera's position for those would test a diagonal
## line the camera never looks along.
static func ray_origin(cam_pos: Vector3, forward: Vector3, orthographic: bool,
		target: Vector3) -> Vector3:
	if not orthographic:
		return cam_pos
	var depth := forward.dot(target - cam_pos)
	return target - forward * depth

## Is there an opaque block on the straight line between the two points?
## `opaque_at` takes a Vector3i cell and answers whether it blocks sight.
## The end cells themselves are not sampled: a camera pressed against a
## wall, or a body standing in tall grass, is not hidden by it.
static func line_clear(from: Vector3, to: Vector3, opaque_at: Callable) -> bool:
	var span := to - from
	var dist := span.length()
	if dist <= STEP:
		return true
	var steps := int(dist / STEP)
	var step := span / float(steps)
	var at := from
	var last := Vector3i(floori(from.x), floori(from.y), floori(from.z))
	var end := Vector3i(floori(to.x), floori(to.y), floori(to.z))
	for i in range(1, steps):
		at += step
		var cell := Vector3i(floori(at.x), floori(at.y), floori(at.z))
		if cell == last or cell == end:
			continue
		last = cell
		if opaque_at.call(cell):
			return false
	return true

## Can a camera with this ray origin rule see a body standing at `feet`?
static func body_in_view(cam_pos: Vector3, forward: Vector3, orthographic: bool,
		feet: Vector3, opaque_at: Callable) -> bool:
	for height in BODY_POINTS:
		var point := feet + Vector3(0, height, 0)
		var origin := ray_origin(cam_pos, forward, orthographic, point)
		if line_clear(origin, point, opaque_at):
			return true
	return false

## The render layers an overhead tag should sit on, given which seats can
## see its player. The spectator camera is always on the list: it is
## nobody's opponent, and the shop-window shot wants the names in it.
static func layers_for(seen_by: Array) -> int:
	var mask := RenderLayers.OVERHEAD_SPECTATOR
	for slot in seen_by:
		if int(slot) >= 0 and int(slot) < RenderLayers.SEATS:
			mask |= RenderLayers.overhead_of(int(slot))
	return mask
