extends SceneTree
## In first person, THE SHOT IS THE SIGHT LINE.
##
##   godot --headless --path <game> \
##     --script res://tests/aim_convergence.gd
##
## Whatever the crosshair is on is what gets hit — not approximately, and
## not at one particular range. That means the projectile's path must lie
## ON the ray from the eye through the crosshair, for its whole length,
## not merely cross it somewhere.
##
## Two goes at this got it wrong, both by trying to correct for a muzzle
## offset instead of removing it:
##
##  - Converging on a fixed 40 blocks. A rifle zeroed at 40m: dead on
##    there, and off by 1.26 blocks at 150 and 2.40 at 250, against a
##    player about 0.6 blocks wide. Long shots sailed past the crosshair.
##  - Converging on the real target. That fixes where the shot ENDS but
##    not where it GOES: it still travels a diagonal chord running beside
##    the sight line the whole way, so it detonates on blocks the
##    crosshair is not on, and near cover it slips round the edge the
##    crosshair is looking past. Aiming at a nearer target steepens the
##    chord, so it was worse up close.
##
## So this checks the whole path, not the endpoint. A test that only
## measured the miss AT THE TARGET passed the second version happily.

## Ranges to sample along the shot, in blocks.
const RANGES := [1.0, 3.0, 8.0, 20.0, 40.0, 80.0, 150.0, 250.0]

## How far the shot may stray from the sight line, anywhere along it. A
## block is 1 wide, so anything approaching half a block can put the shot
## in the wrong cell.
const ALLOWED := 0.02

var _failures := 0
var _checks := 0

func _initialize() -> void:
	var looks: Array = [
		Vector3(0, 0, -1),
		Vector3(1, 0, -1).normalized(),
		Vector3(0.3, -0.25, -1).normalized(),
		Vector3(-0.8, 0.15, -1).normalized(),
		Vector3(0, -0.9, -1).normalized(),
	]
	for look: Vector3 in looks:
		_check(look)
	_check_lead_is_cosmetic()
	print("  (for the record — a muzzle 0.3 to the side, converged on the "
		+ "target, strays %.2f blocks from the sight line half way to a "
		% _legacy_stray(80.0) + "target at 80)")
	if _checks == 0:
		# A run that measured nothing is a FAILURE, not a pass. The first
		# version of this reported "PASS — 0 samples" when the call it was
		# testing could not even be loaded.
		print("aim_convergence: FAIL — nothing was measured")
		quit(1)
	if _failures == 0:
		print("aim_convergence: PASS — %d samples, the shot never leaves the "
			% _checks + "sight line by more than %.2f blocks" % ALLOWED)
		quit(0)
	else:
		print("aim_convergence: FAIL — %d samples off the sight line" % _failures)
		quit(1)

## Asks the REAL rule — Weapons.shot_ray() — where the shot starts and
## which way it goes. Not a copy of it: the previous version of this test
## reimplemented the formula, so it could pass while the game did
## something else entirely, and that is exactly what happened.
func _check(look: Vector3) -> void:
	var eye := Vector3(0, 1.6, 0)
	var ray := Weapons.shot_ray(eye, look, true, 0)
	var origin: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	for travelled: float in RANGES:
		_checks += 1
		var at := origin + dir * travelled
		# Distance from the sight ray (eye, look).
		var along := (at - eye).dot(look)
		var stray := (at - (eye + look * along)).length()
		if stray > ALLOWED:
			_failures += 1
			if _failures <= 8:
				print("  look %s at %.0f blocks: %.3f off the sight line"
					% [look, travelled, stray])

## The muzzle lead is a DRAWING trick and must stay one.
##
## OrbView draws the first few frames of a shot down and to the right, so
## it looks like it left the gun rather than the middle of your face. The
## shot's real position must be untouched by that — the moment the offset
## leaks into the simulation it is the muzzle-offset bug again, with all
## the same consequences.
##
## This checks the offset decays to nothing and never exceeds what it
## claims, so even the drawn mesh cannot wander somewhere silly.
func _check_lead_is_cosmetic() -> void:
	var fwd := Vector3(0, 0, -1)
	# It must be gone by the time it claims to be gone...
	_checks += 1
	var after: Vector3 = Weapons.muzzle_lead(fwd, Weapons.MUZZLE_LEAD)
	if after.length() > 0.0001:
		_failures += 1
		print("  muzzle lead still %.4f blocks at %.3fs, should be nothing"
			% [after.length(), Weapons.MUZZLE_LEAD])
	# ...it must never be big enough to look like a different shot...
	_checks += 1
	var biggest := 0.0
	var t := 0.0
	while t < Weapons.MUZZLE_LEAD * 3.0:
		biggest = maxf(biggest, (Weapons.muzzle_lead(fwd, t) as Vector3).length())
		t += 0.005
	if biggest > 0.5:
		_failures += 1
		print("  muzzle lead peaks at %.2f blocks — too far to be cosmetic"
			% biggest)
	# ...and it must actually DO something at the start, or the whole
	# point of it is missing and this test is watching nothing.
	_checks += 1
	if (Weapons.muzzle_lead(fwd, 0.0) as Vector3).length() < 0.1:
		_failures += 1
		print("  muzzle lead does nothing at the muzzle — is it wired up?")

## What a side-mounted muzzle converging on its target costs HALF WAY
## there — the part the endpoint-only test could not see.
func _legacy_stray(target_range: float) -> float:
	var eye := Vector3(0, 1.6, 0)
	var look := Vector3(0, 0, -1)
	var side := look.cross(Vector3.UP).normalized()
	var origin := eye + Vector3(0, -0.34, 0) + side * 0.3 + look * 0.3
	var aim := eye + look * target_range
	var dir := (aim - origin).normalized()
	var at := origin + dir * ((aim - origin).length() * 0.5)
	var along := (at - eye).dot(look)
	return (at - (eye + look * along)).length()
