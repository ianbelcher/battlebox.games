class_name TagMode
extends GameMode
## TAG: somebody is It, It is twice the size and twice as fast, and It
## catches you by reaching out and touching you. Then you are It.
##
## NOBODY IS EVER KNOCKED OUT. There are no hearts in this game, nothing
## to shoot and nothing to shoot with — the only weapon is a hand, and
## what a hand does is written in on_melee below rather than in the
## weapon table, because a hand that took hearts off somebody would be a
## sword with a friendlier name.
##
## WHAT THIS MODE IS FOR, beyond being a game four-year-olds already know
## the rules to: it is the second caller of everything Giants added, and
## it pulls in the opposite direction on every one of them. Giants wants
## size without speed; Tag wants both. Giants wants every weapon and
## crates that make you bigger; Tag wants one weapon, no crates, and six
## blocks to build a hiding place out of. Giants wants a melee swing to
## knock somebody out; Tag wants it to move who is It. A seam that both
## of these fit through is a seam, and not a Giants-shaped hole with a
## general name.

# ---- THE KNOBS ---------------------------------------------------------

## It is TWICE THE SIZE AND TWICE THE SPEED. The size is so that you can
## see across a field who is chasing you — the one thing a game of tag
## with a hundred players in it absolutely has to communicate — and the
## speed is what makes being chased feel like being chased. These are
## separate settings on the platform (GameMode.start_size and
## speed_scale) precisely so that this mode can set both while Giants
## sets only the first.
const IT_SIZE := 2.0
const IT_SPEED := 2.0

## ONE It FOR EVERY EIGHT PLAYERS, and never fewer than one. A single It
## chasing ninety-nine people is not a game, it is a very long walk; a
## dozen Its chasing eighty-eight is the enormous game of tag that a room
## with a hundred seats in it is for.
const PLAYERS_PER_IT := 8

## What you can build with. Six blocks, and they are the six a child
## reaches for when what they want is somewhere to hide: something solid,
## something they can see out of, and something soft to land on.
const BLOCKS: Array = [Blocks.PLANKS, Blocks.COBBLE, Blocks.GLASS,
	Blocks.WOOL_RED, Blocks.WOOL_BLUE, Blocks.SNOW]

## The two sides. A player is on one or the other and being tagged moves
## them across, where they stand, without being sent anywhere.
const RUNNERS := 0
const IT := 1

func _init() -> void:
	key = "tag"
	label = "Tag"
	note = "It is twice the size and twice as fast. Do not get touched"

func has_rounds() -> bool:
	return true

func has_clock() -> bool:
	return true

## NOBODY GOES DOWN, so there is nothing for the revive ladder, the
## knockout feed or the hearts on the HUD to do. This is also what stops
## the platform ending the round the moment one side has nobody standing:
## in this game everybody is always standing.
func has_knockouts() -> bool:
	return false

## Two sides, and they are what they are. The front page does not ask.
func picks_teams() -> bool:
	return false

func uses_bot_hearts() -> bool:
	return false

func team_names() -> Array:
	return ["Runners", "It"]

func kicker() -> String:
	return "TAG"

# ---- the round ---------------------------------------------------------

## HOW MANY ITS a room of this many people gets. Static and world-free
## so that the ratio can be checked directly — "how many of them are
## chasing" is exactly the kind of number that is wrong by one at the
## ends and looks fine in the middle.
static func it_count(players: int) -> int:
	return clampi(players / PLAYERS_PER_IT, 1, maxi(players, 1))

## DEAL THE ITS. Called when the lobby opens and again at the drop, so a
## round always starts with the right number of them however many people
## turned up — and a player who joins halfway through comes in as a
## runner (joiner_team below), which is the kind answer.
func deal_teams(world: Node) -> void:
	var ids: Array = world.roster().keys()
	ids.sort()      # the same deal for the same room, not a fresh shuffle
	if ids.is_empty():
		return
	var wanted := it_count(ids.size())
	var picked: Dictionary = {}
	for i in mini(wanted, ids.size()):
		picked[str(ids[randi() % ids.size()])] = true
	# Sampling with replacement can land on the same player twice, which
	# would quietly deal fewer Its than asked for. Top up in order rather
	# than spinning on the random pick.
	for id: String in ids:
		if picked.size() >= wanted:
			break
		picked[id] = true
	for id: String in ids:
		world.bodies.set_team(id, IT if picked.has(id) else RUNNERS)

func round_seconds(world: Node) -> float:
	if float(world.storm_minutes) >= 59.0:
		return 1.0e9
	return float(world.storm_minutes) * 60.0

## IT WINS BY CATCHING EVERYONE. Not a likely ending with a hundred
## players and a three-minute clock, which is the point — it is the
## ending that exists so that the chase has somewhere to go.
func winner(world: Node, _teams_alive: Array) -> int:
	for id: String in world.roster().keys():
		if int(world.roster()[id].get("team", RUNNERS)) == RUNNERS:
			return CONTINUE
	return IT

## THE CLOCK RAN OUT AND THE RUNNERS ARE STILL RUNNING, so the runners
## win. Every player who is It at that moment is It at the end, which is
## the whole scoreboard this game needs.
func on_time_up(world: Node) -> void:
	var caught: Array = []
	for id: String in world.roster().keys():
		if int(world.roster()[id].get("team", RUNNERS)) == IT:
			caught.append(str(world.roster()[id].get("name", "?")))
	if caught.is_empty():
		world.cl_fanfare.rpc("The runners got away", RUNNERS)
	else:
		world.cl_fanfare.rpc("Time! Still It: %s" % ", ".join(caught), IT)
	world.battle.finish(RUNNERS)

## A LATE ARRIVAL RUNS. Walking into a game and being immediately the one
## everybody is running away from is a bad first ten seconds.
func joiner_team(_world: Node, _id: String, _balanced: int) -> int:
	return RUNNERS

# ---- the tag itself ----------------------------------------------------

## THE WHOLE GAME, in one function.
##
## It touches a runner: they swap. The one who was It is a runner again,
## person-sized and at a person's pace; the one who was touched is It,
## twice the size and twice as fast, standing exactly where they were
## standing. Nobody is moved, nobody loses a heart, and there is no way
## to be out.
##
## A runner touching anybody does nothing at all — runners have the same
## hand, and a game where the person being chased can tag back is a game
## that never settles on who is It.
func on_melee(world: Node, attacker: String, target: String) -> String:
	if not _is_it(world, attacker) or _is_it(world, target):
		return "none"
	_become(world, attacker, RUNNERS)
	_become(world, target, IT)
	# NOT Sfx.play() — a mode that names an autoload cannot be loaded by a
	# --script run, and the front page's tests load every mode. The
	# fanfare carries its own sound on the clients that hear it.
	world.cl_fanfare.rpc("%s is It!" % _name_of(world, target), IT)
	return "tag"

func _is_it(world: Node, id: String) -> bool:
	return int(world.roster().get(id, {}).get("team", RUNNERS)) == IT

func _become(world: Node, id: String, team: int) -> void:
	world.bodies.set_team(id, team)
	world.bodies.set_size(id, IT_SIZE if team == IT else BodySize.PERSON)
	world.bodies.set_speed(id, IT_SPEED if team == IT else 1.0)

func _name_of(world: Node, id: String) -> String:
	return str(world.roster().get(id, {}).get("name", "Somebody"))

# ---- per player --------------------------------------------------------

func start_size(world: Node, id: String) -> float:
	return IT_SIZE if _is_it(world, id) else BodySize.PERSON

func speed_scale(world: Node, id: String) -> float:
	return IT_SPEED if _is_it(world, id) else 1.0

## ONE WEAPON, WHICH IS A HAND. Six blocks to build with, no prefab kits
## (a game of tag does not want somebody stamping a castle down in the
## middle of it) and no supply crates at all — there is nothing in this
## game to find.
func loadout(_world: Node) -> Loadout:
	var out := Loadout.new()
	out.weapons = [Weapons.HAND]
	out.blocks = BLOCKS
	out.kits = Loadout.none()
	out.crate_loot = Loadout.none()
	out.start = [Weapons.HAND]
	return out
