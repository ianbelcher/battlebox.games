class_name VehicleGeom
## THE SHAPE AND THE PHYSICS OF A THING YOU CAN STAND ON AND DRIVE.
##
## Boats for the water maps, cars for the dry ones. They are the same
## object with different numbers: a flat deck, a heading, one driver and
## as many passengers as fit on it.
##
## WHY A SEPARATE FILE. Everything here is static and pure — no world, no
## roster, no autoloads, nothing that has to exist first. `--script` runs
## have no autoloads at all, so this is the only way any of it can be
## tested, and the part worth testing is precisely this: whether somebody
## standing on the back of a boat is still standing on the back of it
## after the boat has turned. That is not something a headless run can
## answer and not something a screenshot can show.
##
## VehicleDirector owns the list of them and who is aboard; this owns
## where they are and what is on them.

const KIND_BOAT := 0
const KIND_CAR := 1

## Twice a run, as asked for. Player.WALK_SPEED is 4.6, so a boat at 9.2
## is exactly double and a car is a shade quicker again because a desert
## is a bigger, emptier place to cross.
const BOAT_SPEED := 9.2
const CAR_SPEED := 11.0
## How fast the nose comes round, in radians a second. Slow enough that a
## boat feels like a boat and a five-year-old can hold a heading.
const BOAT_TURN := 1.5
const CAR_TURN := 2.1
## Nothing stops dead. Coasting is most of what makes driving feel like
## driving rather than like walking a very large hat.
const DRAG := 2.6

## Deck size, as half-extents in blocks. A boat is longer than it is wide;
## a car is nearly square and smaller, because it has to fit between
## things.
static func half_length(kind: int) -> float:
	return 2.6 if kind == KIND_BOAT else 1.9

static func half_width(kind: int) -> float:
	return 1.5 if kind == KIND_BOAT else 1.4

## How far above the hull's origin the deck surface is — where feet go.
static func deck_height(kind: int) -> float:
	return 0.55 if kind == KIND_BOAT else 0.75

static func top_speed(kind: int) -> float:
	return BOAT_SPEED if kind == KIND_BOAT else CAR_SPEED

static func turn_rate(kind: int) -> float:
	return BOAT_TURN if kind == KIND_BOAT else CAR_TURN

## A point in the vehicle's own frame: x across, z along, y up.
##
## This pair is the whole trick behind "a number of other players can jump
## on it and will remain in the same place on the boat". A rider's spot is
## remembered in THIS frame, and turned back into a world position every
## frame — so when the boat turns, the rider goes round with it and stays
## exactly where they were standing.
static func to_local(origin: Vector3, yaw: float, point: Vector3) -> Vector3:
	var d := point - origin
	var c := cos(-yaw)
	var s := sin(-yaw)
	return Vector3(d.x * c - d.z * s, d.y, d.x * s + d.z * c)

static func to_world(origin: Vector3, yaw: float, local: Vector3) -> Vector3:
	var c := cos(yaw)
	var s := sin(yaw)
	return origin + Vector3(local.x * c - local.z * s, local.y,
		local.x * s + local.z * c)

## Is somebody standing on this deck?
##
## Generous upwards and mean downwards. A player's feet sit a hair above
## the deck when they land and a hair below it while they settle, and a
## rider who is dropped for one frame of that is a rider thrown off a
## moving boat.
static func on_deck(kind: int, origin: Vector3, yaw: float,
		feet: Vector3) -> bool:
	var local := to_local(origin, yaw, feet)
	if absf(local.x) > half_width(kind) or absf(local.z) > half_length(kind):
		return false
	var above := local.y - deck_height(kind)
	return above > -0.45 and above < 1.6

## Where the deck surface is, under a given point.
static func deck_at(kind: int, origin: Vector3) -> float:
	return origin.y + deck_height(kind)

## ONE STEP OF DRIVING. `throttle` and `steer` are both -1..1, straight off
## a stick. Returns [origin, yaw, speed].
##
## Turning only bites when moving, which is what stops a stationary boat
## spinning on the spot like a fairground ride — and is also true of every
## real boat and car.
static func drive(kind: int, origin: Vector3, yaw: float, speed: float,
		throttle: float, steer: float, delta: float) -> Array:
	var want := clampf(throttle, -1.0, 1.0) * top_speed(kind)
	# Reverse is half pace. It is for getting off a sandbank, not for
	# racing backwards.
	if want < 0.0:
		want *= 0.5
	var next_speed := move_toward(speed, want, top_speed(kind) * delta * 2.0)
	if is_zero_approx(throttle):
		next_speed = move_toward(next_speed, 0.0, DRAG * delta)
	var bite := clampf(absf(next_speed) / top_speed(kind), 0.0, 1.0)
	var next_yaw := yaw - clampf(steer, -1.0, 1.0) * turn_rate(kind) * bite * delta
	var heading := Vector3(sin(next_yaw), 0.0, cos(next_yaw))
	return [origin + heading * next_speed * delta, next_yaw, next_speed]
