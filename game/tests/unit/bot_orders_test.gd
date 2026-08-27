extends TestCase
## The two decisions a team of computer players makes together.
##
## Both of these have been got wrong before in ways no other check in this
## repository could see: a round runs, the clock ticks, nothing errors, and
## every side either sits on its own flag for ten minutes or scatters into
## nine attacks of one. The failures are RATIOS, so they are exactly the
## kind of thing a pure module can be asked about directly.

# ---- how many stay home ------------------------------------------------

func test_somebody_always_goes_out() -> void:
	# The invariant that decides whether the mode is a game at all. A side
	# that keeps everybody home cannot take a flag, and a round where no
	# flag is taken pays every survivor nothing.
	for size in range(2, 26):
		for threat in [0, 1, 3, 9]:
			var home := BotOrders.keepers(size, size / 2, threat, 2)
			check(home < size,
				"team of %d with %d at the door kept everybody home"
					% [size, threat])

func test_somebody_always_stays() -> void:
	for size in range(2, 26):
		var home := BotOrders.keepers(size, 0, 0, 3)
		check(home >= 1, "team of %d left its flag unguarded" % size)

func test_a_lone_player_goes_out() -> void:
	# Guarding a base nobody is walking towards is not a strategy, it is a
	# way of not playing — and with one player there is nobody else to do
	# the attacking.
	equal(BotOrders.keepers(1, 1, 0, 2), 0, "one player attacks")

func test_enemies_at_the_door_bring_people_home() -> void:
	var quiet := BotOrders.keepers(10, 5, 0, 2)
	var busy := BotOrders.keepers(10, 5, 3, 2)
	check(busy > quiet,
		"three enemies on our flag should be worth more defenders")

func test_the_recall_is_capped() -> void:
	# A doorstep full of enemies must not pull the WHOLE side home: a team
	# that does that can be pinned for the round by one attacker who keeps
	# walking past.
	var swamped := BotOrders.keepers(12, 6, 40, 2)
	check(swamped < 12, "an overwhelming threat still leaves somebody out")

func test_a_quiet_doorstep_thins_the_guard() -> void:
	# The other half of "they all just huddle": in a siege, defence is the
	# default, so without something actively spending the guard the
	# default is all anybody ever does.
	check(BotOrders.keepers(10, 5, 0, 2) < 5,
		"nobody at the door should mean one fewer on the wall")

func test_nothing_left_to_take_means_everybody_holds() -> void:
	equal(BotOrders.keepers(8, 4, 0, 0), 8,
		"with no enemy flag standing there is nothing to attack")

func test_attackers_and_keepers_add_up() -> void:
	for size in range(1, 20):
		for threat in [0, 2]:
			equal(BotOrders.keepers(size, size / 2, threat, 2)
				+ BotOrders.attackers(size, size / 2, threat, 2), size,
				"the two halves of a team of %d must be the whole of it" % size)

# ---- which flag they go for --------------------------------------------

func test_an_empty_board_has_no_target() -> void:
	equal(BotOrders.pick_target([], 3), -1, "nothing standing, nowhere to go")

func test_the_nearest_flag_wins_when_nobody_has_chosen() -> void:
	var options := [{"dist": 90.0, "friends": 0}, {"dist": 40.0, "friends": 0}]
	equal(BotOrders.pick_target(options, 5), 1, "nearest, all else equal")

func test_a_bot_joins_its_team_mates() -> void:
	# THE WHOLE POINT. A flag forty blocks further away, with three of your
	# own side already walking at it, is the better place to be — three
	# together take a base and one alone feeds it.
	var options := [{"dist": 80.0, "friends": 3}, {"dist": 50.0, "friends": 0}]
	equal(BotOrders.pick_target(options, 5), 0,
		"go where your side is going")

func test_but_not_across_the_whole_map() -> void:
	# The pull is worth a detour, not a pilgrimage. With the friend count
	# capped, a flag far enough away loses however popular it is.
	var options := [{"dist": 240.0, "friends": 3}, {"dist": 30.0, "friends": 0}]
	equal(BotOrders.pick_target(options, 5), 1,
		"a flag on the far side of the map is still a long way")

func test_a_full_flag_is_passed_over() -> void:
	var options := [{"dist": 10.0, "friends": 6}, {"dist": 70.0, "friends": 0}]
	equal(BotOrders.pick_target(options, 6), 1,
		"the surge is capped: the rest look elsewhere")

func test_when_everything_is_full_it_still_picks_somewhere() -> void:
	# Returning -1 here is how a bot ends up standing still doing nothing,
	# which is the failure this whole file exists to prevent.
	var options := [{"dist": 10.0, "friends": 9}, {"dist": 70.0, "friends": 7}]
	var choice := BotOrders.pick_target(options, 3)
	check(choice >= 0, "somewhere is always better than nowhere")
	equal(choice, 1, "the least crowded of a crowded board")

func test_every_flag_gets_somebody() -> void:
	# Deal a whole team out one at a time — scouts first, then everybody
	# else choosing from what the ones before them chose — and check no
	# standing flag is ignored. This is the emergent behaviour the module
	# exists for, and it cannot be read off any single call.
	#
	# It is also the invariant scoring ALONE breaks: without the scouts,
	# twelve attackers over three flags came out six, six and none, and a
	# flag nobody walks at belongs to a team that cannot lose.
	var commit := _deal(12, 3)
	for t in 3:
		check(commit[t] > 0, "flag %d had nobody sent at it: %s" % [t, str(commit)])

## One team's worth of attackers, dealt the way the director deals them.
func _deal(attackers: int, targets: int) -> Array:
	var commit: Array[int] = []
	commit.resize(targets)
	var cap := BotOrders.surge_cap(attackers, targets)
	for index in attackers:
		var scout := BotOrders.scout_target(index, targets)
		if scout >= 0:
			commit[scout] += 1
			continue
		var options: Array = []
		for t in targets:
			options.append({"dist": 40.0 + float(t) * 25.0, "friends": commit[t]})
		var choice := BotOrders.pick_target(options, cap)
		if choice < 0:
			fail("an attacker was left with nowhere to go")
			return commit
		commit[choice] += 1
	return commit

func test_a_team_actually_concentrates() -> void:
	# The other side of the same run: once the board is covered they must
	# not go on splitting evenly, or nothing has changed from dealing
	# cards and every attack is outnumbered everywhere.
	var commit := _deal(12, 3)
	var most := 0
	for t in 3:
		most = maxi(most, commit[t])
	check(most >= 5,
		"twelve attackers over three flags should mass somewhere: %s" % str(commit))

func test_the_scouts_go_out_one_each() -> void:
	equal(BotOrders.scout_target(0, 3), 0, "the first attacker takes the first flag")
	equal(BotOrders.scout_target(2, 3), 2, "and the third takes the third")
	equal(BotOrders.scout_target(3, 3), -1,
		"the fourth is free to join whoever it likes")
	equal(BotOrders.scout_target(0, 0), -1, "no flags, no scouts")

func test_one_flag_takes_the_lot() -> void:
	equal(BotOrders.surge_cap(7, 1), 7, "with one target there is no sharing")

func test_the_cap_is_never_less_than_a_squad() -> void:
	for targets in range(1, 9):
		check(BotOrders.surge_cap(4, targets) >= BotOrders.SURGE_MIN,
			"a fair share of one is nine attacks of one again")

# ---- sticking to a decision --------------------------------------------

func test_a_choice_is_committed_for_a_while() -> void:
	check(not BotOrders.may_rethink(2000, true),
		"changing your mind two seconds in is never deciding")

func test_a_flag_that_has_fallen_frees_you_immediately() -> void:
	check(BotOrders.may_rethink(500, false),
		"there is no point walking at a flag that is already gone")

func test_the_commitment_does_run_out() -> void:
	check(BotOrders.may_rethink(BotOrders.COMMIT_MS + 1, true),
		"a raid that never arrives has to be reconsidered eventually")
