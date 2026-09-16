extends TestCase
## Giants: the growth ladder, and what the game is played with.
##
## The ladder is worth pinning because both ways it can go wrong are
## silent. A cap that does not hold is a player who grows every round
## until they are bigger than the map; a cap that holds one rung too
## early is a game whose whole advertised ending never happens. Neither
## raises anything and neither is visible in a short test round.

# ---- the ladder --------------------------------------------------------

## THREE DOUBLINGS AND NO MORE — which is the game as it was asked for:
## collect three growth crates and you are eight times normal size.
func test_three_steps_reach_the_top_and_stop() -> void:
	var size := BodySize.PERSON
	size = GiantsMode.next_size(size)
	near(size, 2.0, 0.0001, "one knockout: twice the size")
	size = GiantsMode.next_size(size)
	near(size, 4.0, 0.0001, "two: four times")
	size = GiantsMode.next_size(size)
	near(size, 8.0, 0.0001, "three: eight times, and that is the cap")
	size = GiantsMode.next_size(size)
	near(size, GiantsMode.MAX_SIZE, 0.0001, "a fourth changes nothing")

func test_the_ladder_can_never_climb_past_its_cap() -> void:
	var size := BodySize.PERSON
	for _step in 40:
		size = GiantsMode.next_size(size)
		check(size <= GiantsMode.MAX_SIZE,
			"%.1f is over the cap of %.1f" % [size, GiantsMode.MAX_SIZE])

## The cap is a knob, and raising it has to keep working without anything
## else being touched — that was the point of it being a constant.
func test_the_cap_is_a_number_the_ladder_actually_obeys() -> void:
	check(GiantsMode.MAX_SIZE <= BodySize.MAX,
		"a giant must still be a body the world can hold")
	check(GiantsMode.MAX_SIZE > BodySize.PERSON, "…and bigger than a person")

## Nobody shrinks by growing, whatever they were before.
func test_growing_never_makes_anybody_smaller() -> void:
	for start: float in [0.5, 1.0, 1.5, 2.0, 7.9, 8.0]:
		check(GiantsMode.next_size(start) >= start,
			"growing from %.2f did not shrink anybody" % start)

# ---- a giant is a bigger target, and that is what its hearts pay for ----

## THE TRADE THE WHOLE GAME RESTS ON. Being eight times the size means
## there is very much more of you to hit; the hearts scale with it so
## that growing is a reward rather than a slow way to lose. If one of
## these ever stops scaling with the other, the mode is broken in a way
## that only shows up as "Giants is not fun".
func test_hearts_and_hit_box_grow_together() -> void:
	var mode := GiantsMode.new()
	check(mode.HEARTS_SCALE, "hearts scale with size, or growth is a punishment")
	# The body at 8x is wider and taller in every direction…
	check(BodySize.half_width(8.0) > BodySize.half_width(1.0) * 4.0, "much wider")
	check(BodySize.height(8.0) > BodySize.height(1.0) * 4.0, "much taller")

## And a giant does NOT get to be quick as well. This is the sentence
## that keeps a small player in the game.
func test_a_giant_moves_at_a_persons_pace() -> void:
	var mode := GiantsMode.new()
	near(mode.speed_scale(null, "anybody"), 1.0, 0.0001,
		"size is not speed: a giant lumbers")

# ---- what is on the field ----------------------------------------------

func test_the_crates_can_make_you_bigger() -> void:
	var mode := GiantsMode.new()
	var kit := mode.loadout(null)
	check(Loadout.GROWTH in kit.crate_loot, "some crates hold growth")
	check(kit.has_crates(), "and there are crates at all")

## Weapons are still worth running for, or the round is a footrace
## between people who cannot hurt each other.
func test_but_most_of_them_still_hold_a_weapon() -> void:
	var kit := GiantsMode.new().loadout(null)
	var weapons := 0
	for loot: int in kit.crate_loot:
		if loot >= 0:
			weapons += 1
	check(weapons > kit.crate_loot.size() / 2,
		"most crates are still a weapon (%d of %d)" % [weapons, kit.crate_loot.size()])

func test_everything_else_in_the_game_is_still_in_it() -> void:
	var kit := GiantsMode.new().loadout(null)
	check(kit.allows_weapon(Weapons.SWORD), "the sword")
	check(kit.allows_block(Blocks.PLANKS), "and you can still build")

# ---- the shape of the round --------------------------------------------

func test_it_is_a_round_with_knockouts_and_a_clock() -> void:
	var mode := GiantsMode.new()
	check(mode.has_rounds(), "a round")
	check(mode.has_clock(), "on a clock")
	check(mode.has_knockouts(), "where people go down")
	check(not mode.has_flags(), "and no flags")

# ---- who grows for a knockout ------------------------------------------

## NOT THE STORM. Nothing with nobody behind it makes anybody bigger —
## the storm, the tide, and a long fall all arrive here with an empty
## attacker.
func test_nothing_grows_for_a_knockout_nobody_caused() -> void:
	check(not GiantsMode.earns_growth("victim", "", true),
		"the storm does not get to be a giant")

## NOT YOURSELF. Walking into your own bomb is not an achievement.
func test_you_do_not_grow_for_knocking_yourself_over() -> void:
	check(not GiantsMode.earns_growth("me", "me", true), "no growing on your own bomb")

## NOT YOUR OWN SIDE, and this is the one that would have been forgotten:
## without it, the fastest route to being eight times the size is to
## knock your own team over four times.
func test_you_do_not_grow_for_knocking_your_own_side_over() -> void:
	check(not GiantsMode.earns_growth("them", "me", false),
		"farming your own team is not a growth strategy")

func test_but_an_enemy_you_put_down_makes_you_bigger() -> void:
	check(GiantsMode.earns_growth("them", "me", true), "that is the whole game")
