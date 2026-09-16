extends TestCase
## Tag: how many are chasing, and what the game is played with.
##
## Tag is also the check that the platform's new seams are seams and not
## Giants-shaped holes. Every assertion below about size, speed and the
## loadout is one where Tag wants the opposite of what Giants wants, and
## both have to be true at once.

# ---- how many are It ---------------------------------------------------

## THERE IS ALWAYS SOMEBODY CHASING. A room of one, two or seven still
## has an It, or the game is a field of people standing about.
func test_a_small_room_still_has_somebody_chasing() -> void:
	for players in range(1, 9):
		check(TagMode.it_count(players) >= 1,
			"%d players and nobody is It" % players)

## AND NOT EVERYBODY. An It cannot tag another It, so a room where
## everyone is It is a room where the game has stopped.
func test_never_everybody() -> void:
	for players in range(2, 101):
		check(TagMode.it_count(players) < players,
			"%d players and every one of them is It" % players)

## ONE IN EIGHT, so a hundred seats is the enormous game of tag a hundred
## seats is for rather than one child walking a very long way.
func test_a_big_room_gets_a_pack_of_them() -> void:
	equal(TagMode.it_count(8), 1, "eight players, one It")
	equal(TagMode.it_count(16), 2, "sixteen, two")
	equal(TagMode.it_count(100), 12, "a hundred, a dozen chasing eighty-eight")

func test_more_players_never_means_fewer_chasing() -> void:
	var last := 0
	for players in range(1, 101):
		var its := TagMode.it_count(players)
		check(its >= last, "%d players deals fewer Its than %d did" % [players, players - 1])
		last = its

# ---- It is bigger AND faster -------------------------------------------

## THE SEAM, PROVED. Giants asks for size at a person's pace; Tag asks
## for both at once. If size and speed were ever derived from one another
## one of these two games would stop working, and this is the assertion
## that would say so.
func test_it_is_twice_the_size_and_twice_the_speed() -> void:
	near(TagMode.IT_SIZE, 2.0, 0.0001, "twice the size, so you can see them coming")
	near(TagMode.IT_SPEED, 2.0, 0.0001, "and twice as fast, so it is a chase")
	check(not is_equal_approx(TagMode.IT_SPEED, GiantsMode.SPEED),
		"the two games disagree about speed, which is the point of the seam")

# ---- one weapon, and it is a hand --------------------------------------

func test_the_only_weapon_is_a_hand() -> void:
	var kit := TagMode.new().loadout(null)
	check(kit.allows_weapon(Weapons.HAND), "the hand")
	check(not kit.allows_weapon(Weapons.SWORD), "and emphatically not the sword")
	equal(kit.weapon_ids().size(), 1, "exactly one weapon in the game")

func test_you_start_holding_it() -> void:
	equal(TagMode.new().loadout(null).start, [Weapons.HAND],
		"there is nothing else to hold")

## The hand has to be a weapon the rest of the game knows about, or it is
## a thing with no icon, no cooldown and no picture in anybody's hand.
func test_the_hand_is_a_real_weapon_in_the_table() -> void:
	var spec := Weapons.spec(Weapons.HAND)
	equal(str(spec.get("name", "")), "Hand", "it is in the registry")
	check(float(spec.get("cooldown", 0.0)) > 0.0, "and it has a swing rate")

func test_there_is_something_to_build_with_but_not_everything() -> void:
	var kit := TagMode.new().loadout(null)
	check(kit.allows_block(Blocks.PLANKS), "somewhere to hide behind")
	check(not kit.allows_block(Blocks.BOOM), "but nothing that goes bang")
	equal(kit.block_ids().size(), TagMode.BLOCKS.size(), "six blocks, and six only")

func test_nothing_to_find_and_nothing_to_stamp() -> void:
	var kit := TagMode.new().loadout(null)
	check(not kit.has_crates(), "no supply crates: there is nothing to find")
	check(not kit.allows_kit(0), "and no dropping a castle into the middle of it")

# ---- the shape of the round --------------------------------------------

## NOBODY IS EVER KNOCKED OUT, which is what stops the platform ending
## the round the instant one side has nobody standing — in this game
## everybody is always standing.
func test_nobody_is_ever_knocked_out() -> void:
	var mode := TagMode.new()
	check(mode.has_rounds(), "it is a round")
	check(mode.has_clock(), "on a clock")
	check(not mode.has_knockouts(), "but nobody goes down")
	check(not mode.picks_teams(), "and the two sides are not up for discussion")

func test_the_sides_are_named_for_what_you_are_doing() -> void:
	equal(TagMode.new().team_names(), ["Runners", "It"], "Runners and It")

## A runner cannot tag back. A game where the person being chased can
## tag the chaser never settles on who is It.
func test_only_it_can_tag() -> void:
	equal(TagMode.RUNNERS, 0, "runners are side 0")
	equal(TagMode.IT, 1, "and It is side 1")
	check(TagMode.RUNNERS != TagMode.IT, "which are two different sides")
