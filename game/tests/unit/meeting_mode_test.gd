extends TestCase
## WHAT A MEETING IS NOT, which is most of what defines it.
##
## Every one of these was a real hole rather than a hypothetical. The kit
## was harmless and the supply crates were still full of rockets, because
## a kit is what you START holding and says nothing about what you can
## pick up. And the seat count was clamped in the lobby and on the front
## page but not in the world, so a room started straight from the
## environment — the whole development loop, and how the container runs
## one — filled an office with eleven computer players.

func _meeting() -> GameMode:
	return GameModes.by_key("meeting")

func test_the_mode_is_registered_and_findable() -> void:
	equal(_meeting().key, "meeting", "by_key finds it")
	check(GameModes.has("meeting"), "the registry has it")

func test_it_is_not_a_round_of_anything() -> void:
	var m := _meeting()
	check(not m.has_rounds(), "no rounds")
	check(not m.has_knockouts(), "no knockouts")
	check(not m.has_clock(), "no clock")
	check(not m.has_flags(), "no flags")
	check(not m.picks_teams(), "no sides to pick")

func test_nobody_is_a_computer_player() -> void:
	check(not _meeting().wants_bots(), "the mode says no")
	check(not GameSetup.uses("players", "meeting"),
		"so the front page does not ask for a seat count")
	# And the seat count it would otherwise have been given is thrown away.
	equal(GameSetup.clean({"mode": "meeting", "players": 20}).players, 0,
		"a seat count that arrives anyway is dropped")

func test_nothing_in_it_can_hurt_anybody() -> void:
	var kit: Loadout = _meeting().loadout(null)
	for id: int in kit.weapon_ids():
		check(id in [Weapons.HAND, Weapons.SPRAYER, Weapons.FLARE,
			Weapons.GRAPPLE],
			"weapon %d (%s) does no damage" % [id, Weapons.spec(id).name])
	for id: int in kit.start:
		check(kit.allows_weapon(id), "what you start holding is in the game")

func test_there_are_no_supply_crates() -> void:
	# The survival director asks exactly this before it scatters any.
	check(not _meeting().loadout(null).has_crates(),
		"a meeting hands out no loot")

func test_it_opens_on_the_office_without_locking_it() -> void:
	equal(GameSetup.suggested_map("meeting"), "office", "suggests the office")
	equal(GameSetup.clean({"mode": "meeting"}).map, "office",
		"and a create with no map named gets one")
	equal(GameSetup.clean({"mode": "meeting", "map": "desert"}).map, "desert",
		"but a map that WAS asked for is honoured")

func test_every_other_mode_still_fills_its_seats() -> void:
	for mode: GameMode in GameModes.ALL:
		if mode.key == "meeting":
			continue
		check(mode.wants_bots(),
			"%s still wants computer players" % mode.key)

## THE FIT-OUT HAS TO BE PLACEABLE, and it very nearly was not: the
## loadout refuses any block outside Blocks.HOTBAR and the server checks
## that on every edit, so an office block listed only in the picker is one
## a child can choose and then watch silently fail to appear.
func test_you_can_actually_build_with_the_office() -> void:
	var kit: Loadout = _meeting().loadout(null)
	for id: int in Blocks.picker_category("office"):
		check(kit.allows_block(id),
			"%s can be placed" % Blocks.info(id).get("name", str(id)))
