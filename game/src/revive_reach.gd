class_name ReviveReach
## CAN THIS PLAYER PICK THAT ONE UP?
##
## A plain radius was not the right shape once being knocked out started
## lifting you ten blocks into the air. Measured straight, a rescuer
## standing directly underneath somebody is four to ten blocks away and
## the pick-up never starts — which is exactly what "they come to me to be
## revived and nothing happens" was. The casualty was over their heads.
##
## So the reach is a COLUMN, not a ball: you have to be beside them on the
## ground, and they can be well above you. Being above THEM is not the
## same thing and is barely allowed — dropping past somebody at speed is
## not helping them.
##
## Pure and on its own, because it is a rule that has already bitten once
## and the only way to check it is to check the arithmetic. A `--script`
## run has no autoloads, so anything that needs the world cannot be
## tested at all.

## How close you have to be, measured on the flat.
const RADIUS := 3.0

## How far ABOVE you the casualty may be. Player.KNOCKOUT_RISE_BLOCKS is
## ten, plus enough slack that arriving while they are still drifting down
## counts — otherwise a rescuer has to guess when to be standing there.
const REACH_UP := 13.0

## And how far below. Small: this is for a step down, not for falling past
## somebody on your way off a cliff.
const REACH_DOWN := 3.0

static func in_reach(body: Vector3, rescuer: Vector3) -> bool:
	var flat := Vector2(body.x - rescuer.x, body.z - rescuer.z).length()
	if flat > RADIUS:
		return false
	var above := body.y - rescuer.y
	return above <= REACH_UP and above >= -REACH_DOWN
