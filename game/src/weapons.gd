class_name Weapons
## The weapon registry. Each entry is self-contained: to add or remove a
## weapon, edit this table and (if it changes terrain) its case in
## WorldNode.sv_shot / OrbView impact handling. Ids are wire format.

## ORDER HERE IS THE ORDER OF THE TOOLS TAB, and the picker is ten wide —
## so the first ten entries are row one and everything after is row two.
## Row one is the sword and the things that shoot; row two is the kit you
## use on each other and the world: flare, smoke, sprayer, wings, paint
## bomb, whistle.
const WEAPONS := [
	# The one weapon everybody starts holding, so it has to be worth
	# holding. It kills outright inside three blocks — see
	# WorldNode.sv_sword_hit — which is the only thing that makes closing
	# the distance on somebody with a gun a plan rather than a mistake.
	{"id": 13, "name": "Sword", "color": Color("dfe4ea"), "cooldown": 0.4, "speed": 1.0,
		"blurb": "Get in CLOSE and it is one hit, one down. Cuts soft blocks too"},
	{"id": 0, "name": "Little Shooter", "color": Color("ffe08a"), "cooldown": 0.09, "speed": 62.0,
		"blurb": "Rapid pellets: break soft blocks, light TNT from afar"},
	{"id": 1, "name": "Medium Shooter", "color": Color("ff7a3d"), "cooldown": 0.35, "speed": 34.0,
		"blurb": "Quick-fire explosions. Steel only chips on a direct hit"},
	{"id": 15, "name": "Big Shooter", "color": Color("d63d2e"), "cooldown": 2.0, "speed": 30.0,
		"blurb": "One shot every two seconds - but the boom is ENORMOUS"},
	{"id": 9, "name": "Napalm Rocket", "color": Color("f2e04a"), "cooldown": 0.7, "speed": 40.0,
		"blurb": "Mid-size blast that leaves quick-burning fire"},
	# A CLIMBING tool, not a travel one — the hook dies ten blocks out
	# sideways (OrbView.GRAPPLE_REACH) and the blurb has to say so, or the
	# first thing anybody tries is the thing it no longer does.
	{"id": 2, "name": "Grapple", "color": Color("c9b3ff"), "cooldown": 0.9, "speed": 70.0,
		"blurb": "Climb anything: hook UP high and get zipped to it"},
	{"id": 12, "name": "Digger", "color": Color("b5975f"), "cooldown": 1.2, "speed": 44.0,
		"blurb": "Drills a 3x3 tunnel 15 blocks through anything soft"},
	{"id": 3, "name": "Freeze Ray", "color": Color("aef7f0"), "cooldown": 0.8, "speed": 44.0,
		"blurb": "Turns water to ice and freezes Grumps solid", "hidden": true},
	{"id": 4, "name": "Block Sucker", "color": Color("62a851"), "cooldown": 0.5, "speed": 44.0,
		"blurb": "Vacuums the hit block into your next slot", "hidden": true},
	{"id": 14, "name": "Flare Gun", "color": Color("ff8ac2"), "cooldown": 3.0, "speed": 26.0,
		"blurb": "A star in YOUR TEAM'S colour, floating down over the field"},
	# Fast on purpose, and faster than anything that does damage. This is
	# not a grenade you lob, it is a POINTER: you are saying "there" to
	# your team mid-fight, and a marker that takes two seconds to sail
	# across the field has already stopped being about where you meant.
	{"id": 19, "name": "Smoke Bomb", "color": Color("9aa6c4"), "cooldown": 4.0, "speed": 78.0,
		"blurb": "One team-coloured marker at a time: THAT is where we're going"},
	{"id": 18, "name": "Paint Sprayer", "color": Color("60d394"), "cooldown": 0.12, "speed": 46.0,
		"blurb": "Paints ONE block in YOUR TEAM'S colour - draw, mark, sign your work"},
	# Wings, retired. They only mattered on the way DOWN from somewhere
	# high, and the grapple is the thing for getting up. Id burned.
	{"id": 11, "name": "Wings", "color": Color("eceff4"), "cooldown": 9.0, "speed": 1.0,
		"blurb": "Hold to glide from high places", "hidden": true},
	{"id": 8, "name": "Paint Bomb", "color": Color("b07df0"), "cooldown": 0.9, "speed": 36.0,
		"blurb": "Splats the landscape into random wool colors"},
	{"id": 10, "name": "Grump Whistle", "color": Color("8a5fd0"), "cooldown": 2.0, "speed": 30.0,
		"blurb": "Summons a wild Grump right there", "hidden": true},
	# Retired, ids left burned so nothing reuses them on the wire:
	#   5  Bridge Gun    6  Party Popper    7  Whirl Wand
	# None of them were any use in a game.
]

## What a player starts a battle holding. Everything else is loot.
## Sword to fight with, and all three TEAM-COLOUR markers: a flare to
## light a spot, a sprayer to paint one, smoke to point at one.
## What you drop in with, per mode. Slot 0 is what you are HOLDING.
##
## Battle royale keeps the sword first: the round opens as a scramble for
## crates and the sword is what stops it being a shoot-out before anyone
## has found anything.
##
## Capture the flag opens with the Little Shooter in hand instead. There is
## no scramble here — you start in your own base, on the ground, and the
## fight comes to you — so starting unable to shoot back is just a player
## standing in a doorway losing.
const STARTING_KIT := [13, 14, 19]          # sword, flare gun, smoke bomb
const STARTING_KIT_CTF := [0, 13, 14, 19]   # + little shooter, held

## THE ORDER OF THE TOOLS PAGE, which is not the order of this file.
##
## The registry's own order is the hotbar's, and it has to stay put — ids
## are wire format and the first ten entries are row one of the old
## layout. What a player wants on the page is grouping: what fights, what
## moves you, what talks to your team. Six to a row.
const TOOL_PAGE_ORDER := [
	13, 0, 1, 15, 9,        # sword, little, medium, big, napalm rocket
	2, 12,                  # grapple, digger
	14, 19, 18, 8,          # flare, smoke, sprayer, paint bomb
]

## Both flag modes get the flag kit: last flag standing is the same board
## with one rule different, and it wants the same tools — more so, since
## the whole round is what you can build before they arrive.
static func starting_kit(mode: String) -> Array:
	return STARTING_KIT_CTF if mode == "ctf" or mode == "holdout" else STARTING_KIT

static func count() -> int:
	return WEAPONS.size()

static func visible_ids() -> Array:
	var out: Array = []
	for w in WEAPONS:
		if not w.get("hidden", false):
			out.append(int(w.id))
	return out

static var _by_id: Dictionary = {}

static func spec(id: int) -> Dictionary:
	if _by_id.is_empty():
		for w in WEAPONS:
			_by_id[int(w.id)] = w
	return _by_id.get(id, WEAPONS[0])

## WHERE A SHOT STARTS AND WHICH WAY IT GOES. Returns [origin, dir].
##
## The single source of truth for it, so tests/aim_convergence.gd can
## check the REAL rule rather than a copy. An earlier test reimplemented
## this and happily passed a version of the code that was wrong in play.
##
## It lives on Weapons rather than on OrbView because OrbView references
## autoloads, and a script that does cannot be loaded by a `--script`
## test run. Weapons is plain data and static functions.
##
## FIRST PERSON: THE SHOT IS THE SIGHT LINE. It starts at the eye and
## travels exactly where the crosshair points, so whatever the crosshair
## is on is what gets hit. Full stop, at any range.
##
## Shots used to leave a muzzle down and to the right of the eye, angled
## inwards to converge on the target. That can only ever be right at ONE
## point: the shot travels a diagonal chord running BESIDE the sight line
## the whole way there, so it detonates on blocks the crosshair is not
## on, and near cover it slips round the edge the crosshair is looking
## past. Converging on the real target rather than a fixed 40 blocks
## fixed the long-range miss and made both of those worse, because it
## steepened the chord. There is no offset to correct now, so there is
## nothing left to get wrong.
static func shot_ray(eye: Vector3, dir: Vector3, fp: bool, kind: int) -> Array:
	if fp or kind == 17:
		# Started just clear of the face so it cannot collide with the
		# shooter on its first step.
		return [eye + dir * 0.45, dir]
	# Third person has no crosshair — aim follows the body — so the shot
	# can come off the hip where it looks like it should.
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.ZERO
	return [eye + Vector3(0, -0.34, 0) + side * 0.3 + dir * 0.3, dir]

## HOW LONG THE SHOT IS DRAWN OFF ITS TRUE PATH, in seconds — about ten
## frames — and how far to the side and below it starts.
const MUZZLE_LEAD := 0.18
const MUZZLE_SIDE := 0.30
const MUZZLE_DROP := 0.30

## A shot that starts in the dead centre of the screen looks like it came
## out of your face. This draws the first few frames down and to the
## right, where the gun is, and blends to nothing.
##
## IT MOVES THE MESH ONLY. The shot's real position — what it hits, what
## it passes, where it lands — never sees this. Aim is the sight line and
## nothing is allowed to bend it, cosmetics least of all.
##
## Here on Weapons rather than on OrbView so tests can load it: a script
## that references autoloads cannot be loaded by a `--script` test run,
## and a test that cannot reach what it is checking passes vacuously.
static func muzzle_lead(vel: Vector3, age: float) -> Vector3:
	var lead := 1.0 - age / MUZZLE_LEAD
	if lead <= 0.0:
		return Vector3.ZERO
	var fwd := vel.normalized()
	var side := fwd.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	# Eased, so it slides back onto the line rather than snapping.
	lead = lead * lead
	return (side * MUZZLE_SIDE + Vector3(0, -MUZZLE_DROP, 0)) * lead
