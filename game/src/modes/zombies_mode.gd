class_name ZombiesMode
extends GameMode
## ZOMBIES: a few survivors against a horde. The people are the
## survivors, with the hearts the settings give them and the usual kit;
## every computer player is a zombie with ONE heart, a sword, and hearts
## that grow back fast — and a zombie that goes down stands straight up
## again where the horde starts. A survivor who goes down comes back as
## a zombie. The survivors win by lasting the round; the horde wins when
## there is nobody left to bite.
##
## Two sides, always, and the front page is not asked how many.
##
## The roster is read through the world (`world.roster()`) rather than
## the Game autoload: a script that names an autoload cannot be loaded by
## a --script test run, and the registry this belongs to is what the
## front page's tests check.

const SURVIVORS := 0
const ZOMBIES := 1

func _init() -> void:
	key = "zombies"
	label = "Zombies"
	note = "A few survivors against a horde with one heart each"

func has_rounds() -> bool:
	return true

func has_clock() -> bool:
	return true

func picks_teams() -> bool:
	return false

func uses_bot_hearts() -> bool:
	return false

func team_names() -> Array:
	return ["Survivors", "Zombies"]

## People on one side, computer players on the other. With nobody human
## in the room two of the computer players stand in for the survivors,
## so a room of bots still has a game in it.
func deal_teams(world: Node) -> void:
	world.team_count = 2
	var roster: Dictionary = world.roster()
	var humans := 0
	for id: String in roster.keys():
		var bot := bool(roster[id].get("bot", false))
		roster[id].team = ZOMBIES if bot else SURVIVORS
		if not bot:
			humans += 1
	if humans == 0:
		var stood := 0
		for id: String in roster.keys():
			if stood >= 2:
				break
			roster[id].team = SURVIVORS
			stood += 1

func joiner_team(world: Node, id: String, _balanced: int) -> int:
	return ZOMBIES if bool(world.roster().get(id, {}).get("bot", false)) else SURVIVORS

func _zombie(world: Node, id: String) -> bool:
	return int(world.roster().get(id, {}).get("team", -1)) == ZOMBIES

func kit(world: Node, id: String) -> Array:
	# A sword and nothing else for the horde; the survivors get the
	# flag-mode kit, which is the one with a gun in it.
	return [Weapons.SWORD] if _zombie(world, id) else Weapons.STARTING_KIT_CTF

func max_hp(world: Node, id: String, base: int) -> int:
	return 1 if _zombie(world, id) else base

func regen_ms(world: Node, id: String) -> int:
	return 800 if _zombie(world, id) else 3000

func on_knockout(world: Node, id: String) -> String:
	return "respawn" if _zombie(world, id) else "convert"

func on_time_up(world: Node) -> void:
	world.battle.finish(SURVIVORS)

func winner(_world: Node, teams_alive: Array) -> int:
	return CONTINUE if teams_alive.has(SURVIVORS) else ZOMBIES
