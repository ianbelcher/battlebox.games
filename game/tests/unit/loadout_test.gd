extends TestCase
## What a game is played with.
##
## The thing worth pinning here is the convention, because it is the sort
## that gets inverted by accident: an EMPTY list means EVERYTHING. Five
## games existed before loadouts and none of them says a word about
## blocks or weapons, so if empty ever came to mean "nothing" they would
## all become games you cannot build in.

# ---- saying nothing means everything -----------------------------------

func test_a_game_that_says_nothing_has_everything() -> void:
	var all := Loadout.everything()
	check(all.allows_weapon(Weapons.SWORD), "the sword")
	check(all.allows_weapon(Weapons.HAND), "and the hand")
	check(all.allows_block(Blocks.PLANKS), "planks")
	check(all.allows_block(Blocks.BOOM), "and the ones that go bang")
	check(all.allows_kit(0), "and every prefab")
	check(all.has_crates(), "and crates on the field")

func test_the_resolved_lists_are_the_whole_game() -> void:
	var all := Loadout.everything()
	equal(all.weapon_ids().size(), Weapons.visible_ids().size(),
		"every weapon that is not hidden")
	equal(all.block_ids().size(), Blocks.HOTBAR.size(), "every placeable block")

# ---- saying something means only that ----------------------------------

func test_a_named_weapon_is_the_only_one() -> void:
	var tag := Loadout.new()
	tag.weapons = [Weapons.HAND]
	check(tag.allows_weapon(Weapons.HAND), "the hand is in")
	check(not tag.allows_weapon(Weapons.SWORD), "and the sword is not")

func test_named_blocks_are_the_only_ones() -> void:
	var tag := Loadout.new()
	tag.blocks = [Blocks.PLANKS, Blocks.GLASS]
	check(tag.allows_block(Blocks.PLANKS), "planks are in")
	check(not tag.allows_block(Blocks.BOOM), "a bomb is not")

## A BLOCK NOBODY MAY EVER PLACE stays unplaceable however generous a
## loadout is. `Blocks.HOTBAR` is the floor under all of this: the
## loadout narrows it and can never widen it.
func test_no_loadout_can_offer_a_block_the_game_does_not_place() -> void:
	var odd := Loadout.new()
	odd.blocks = [Blocks.BEDROCK, 60000]
	check(not odd.allows_block(60000), "an id that is not a block at all")

# ---- the empty-list trap -----------------------------------------------

## THE ONE THAT WOULD HAVE BITTEN. "No kits at all" cannot be said with
## an empty list, because empty already means every kit — so it is said
## with a list that matches nothing.
func test_no_kits_is_not_the_same_as_every_kit() -> void:
	var none := Loadout.new()
	none.kits = Loadout.none()
	check(not none.allows_kit(0), "the first prefab is out")
	check(not none.allows_kit(41), "and so is the last")
	var every := Loadout.new()
	check(every.allows_kit(0), "…where saying nothing leaves them all in")

func test_a_game_with_no_crates_places_none() -> void:
	var bare := Loadout.new()
	bare.crate_loot = Loadout.none()
	check(not bare.has_crates(), "nothing to find, so nothing scattered")
	check(Loadout.everything().has_crates(), "…unlike every other game")

# ---- what is in the box ------------------------------------------------

func test_crate_loot_comes_from_the_game_when_it_names_any() -> void:
	var giants := Loadout.new()
	giants.crate_loot = [Loadout.GROWTH]
	for _i in 12:
		equal(giants.roll_crate(), Loadout.GROWTH, "only growth in these crates")

func test_and_from_the_usual_pool_when_it_does_not() -> void:
	var all := Loadout.everything()
	for _i in 24:
		check(all.roll_crate() in Weapons.CRATE_POOL, "a weapon from the usual pool")

## Growth is not a weapon id and must never be mistaken for one — the
## crate machinery tells them apart by the sign, so this is load-bearing.
func test_the_special_loot_kinds_can_never_be_a_weapon() -> void:
	check(Loadout.GROWTH < 0, "special loot is negative")
	for id: int in Weapons.visible_ids():
		check(id >= 0, "…and every real weapon is not")
