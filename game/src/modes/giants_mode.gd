class_name GiantsMode
extends GameMode
## GIANTS: everybody starts the same size, and every knockout makes the
## one who landed it twice as big. The round ends as a fight between two
## or three things the size of houses, standing among people who are
## still the size of people.
##
## THE SIZE LIVES HERE, the same way the storm lives in battle_mode.gd
## and the tide lives in king_hill_mode.gd. The platform knows how to
## make somebody a given size and how to tell everyone about it
## (`world.bodies.set_size`, body_size.gd); what makes anybody grow is
## this file's and nothing else's.
##
## WHY GROWING IS NOT SIMPLY WINNING. A giant is a bigger target in the
## most literal sense — the hit box is the body, so at eight times the
## size there is sixty-four times as much of you to shoot at. The hearts
## are what pay for that: they scale too, so a giant takes longer to
## bring down at exactly the rate it is easier to hit. What a giant does
## NOT get is speed. It runs at a person's pace, which at eight times the
## size reads as lumbering, and that is the hole a small player plays
## through: you cannot outfight a giant but you can outrun one, and it
## cannot follow you into a cave or a fort because it does not fit.

# ---- THE KNOBS. Everything about how this game feels is these four
# ---- numbers, on purpose: they are meant to be edited.

## What one knockout, or one Growth Crate, multiplies you by.
const GROWTH := 2.0

## HOW BIG A GIANT MAY GET. Eight is three doublings — a body 14.4 blocks
## tall and 6.4 wide, which cannot enter any building, any cave or any
## fort on any map, and on the smallest world is a sixth of it across.
## That is the intended shape of the endgame and not an accident.
##
## Raise it to 16.0 for giants twice that again; nothing else has to
## change, and BodySize.MAX is the only thing above it (a body taller
## than the 80-block world could never stand up in it).
const MAX_SIZE := 8.0

## A GIANT MOVES AT A PERSON'S PACE. Not a typo and not an oversight:
## size and speed are separate knobs (GameMode.speed_scale) precisely so
## that this can be 1.0 while Tag's is 2.0. Being twice the size at the
## same speed FEELS like moving at half speed, which is what a giant
## should feel like from the inside.
const SPEED := 1.0

## Do hearts scale with size? See the note at the top for why they
## should. Set false and growth becomes pure liability.
const HEARTS_SCALE := true

## How much of the loot on the field makes you bigger rather than better
## armed, as repetition in the crate pool — the same way Weapons.CRATE_POOL
## expresses rarity. Four in fourteen: common enough that a round always
## has some giants in it, rare enough that a weapon is still worth
## running for.
const CRATE_POOL: Array = [Loadout.GROWTH, Loadout.GROWTH, Loadout.GROWTH,
	Loadout.GROWTH, 0, 1, 1, 2, 9, 12, 12, 15, 15, 19]

func _init() -> void:
	key = "giants"
	label = "Giants"
	note = "Every knockout makes you twice the size"

func has_rounds() -> bool:
	return true

func has_clock() -> bool:
	return true

# ---- the round ---------------------------------------------------------

## Unlimited is a clock that never runs out, and the round ends when one
## side is left — the same convention BattleMode.round_seconds uses.
func round_seconds(world: Node) -> float:
	if float(world.storm_minutes) >= 59.0:
		return 1.0e9
	return float(world.storm_minutes) * 60.0

func winner(_world: Node, teams_alive: Array) -> int:
	if teams_alive.size() > 1:
		return CONTINUE
	return int(teams_alive[0]) if teams_alive.size() == 1 else -1

## SOMEBODY WENT DOWN, so somebody grows.
##
## The one who landed it doubles. The one who went down goes back to the
## size of a person — losing everything you had grown is what makes a
## giant worth being, and it is also the only thing stopping a round
## ratcheting permanently upward until everyone is enormous.
##
## "rules" is returned, so the ordinary revive ladder applies: a team-mate
## can still come and pick you up, and you stand up person-sized to start
## again. Being knocked out in this game costs you your size, not your
## round.
func on_knockout(world: Node, id: String, attacker: String) -> String:
	world.bodies.set_size(id, BodySize.PERSON)
	var known: bool = not attacker.is_empty() and world.roster().has(attacker)
	if earns_growth(id, attacker, known and world.teams_differ(attacker, id)):
		_grow(world, attacker)
	return "rules"

## DOES THIS KNOCKOUT MAKE ANYBODY BIGGER?
##
## Three things do not: the storm, the tide and a long fall, which have
## nobody behind them; knocking yourself over; and knocking over somebody
## on your own side, which would otherwise make farming your own team the
## fastest way to become a giant.
##
## Static and world-free so it can be asked directly — the whole rule is
## three negatives and the one that gets forgotten is always the last.
static func earns_growth(id: String, attacker: String, enemies: bool) -> bool:
	if attacker.is_empty() or attacker == id:
		return false
	return enemies

## A GROWTH CRATE. The other way up the ladder, and the reason the round
## does not consist entirely of whoever got the first kill: three of
## these and a player who has knocked nobody over is the size of the
## player who has knocked three people over.
func on_crate_taken(world: Node, id: String, loot: int) -> void:
	if loot != Loadout.GROWTH:
		return
	_grow(world, id)

## ONE RUNG UP THE LADDER. Static and world-free so that
## tests/unit/giants_test.gd can walk the whole ladder without a game
## running — the cap is the kind of thing that is either exactly right or
## quietly lets somebody grow forever, and neither shows up in a log.
static func next_size(current: float) -> float:
	return minf(maxf(current, BodySize.PERSON) * GROWTH, MAX_SIZE)

## TWICE AS BIG, up to the cap. Hearts come with it because
## `world.bodies.set_size` sends them — max_hp below is what makes them
## scale, and it is asked again on the way out of that call.
##
## A player already at the cap simply stays there rather than being told
## they have wasted a pick-up; there is nothing on screen that could say
## so that a five-year-old would read.
func _grow(world: Node, id: String) -> void:
	var was: float = world.bodies.size_of(id)
	var now := next_size(was)
	if is_equal_approx(was, now):
		return
	world.bodies.set_size(id, now)
	# TOP THE HEARTS UP TO THE NEW BAR, rather than leaving a giant with
	# a person's worth rattling around in it. Growing is a reward; a
	# reward that leaves you on two hearts out of sixty-four would be a
	# punishment wearing its coat.
	var state: Dictionary = world.player_state.get(id, {})
	if not state.is_empty():
		state.hp = world.max_hp(id)
		world.send_hearts(id)
	world.cl_fanfare.rpc("%s is getting BIGGER" % _name_of(world, id),
		int(world.roster().get(id, {}).get("team", -1)))

func _name_of(world: Node, id: String) -> String:
	return str(world.roster().get(id, {}).get("name", "Somebody"))

# ---- per player --------------------------------------------------------

## Everybody starts the same size. The whole game is the distance from
## here.
func start_size(_world: Node, _id: String) -> float:
	return BodySize.PERSON

func speed_scale(_world: Node, _id: String) -> float:
	return SPEED

## HEARTS IN PROPORTION TO SIZE. Eight becomes sixteen, thirty-two,
## sixty-four — and the HUD draws the same eight hearts draining more
## slowly (Player.hearts_shown), so nothing on screen grows with this and
## there is no number anywhere for a child to have to read.
func max_hp(world: Node, id: String, base: int) -> int:
	if not HEARTS_SCALE:
		return base
	return maxi(1, int(round(float(base) * world.bodies.size_of(id))))

## Everything in the game is available; what is different about Giants is
## what the crates hold.
func loadout(_world: Node) -> Loadout:
	var out := Loadout.new()
	out.crate_loot = CRATE_POOL
	return out
