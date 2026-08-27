extends TestCase
## What a computer player does about being shot at.
##
## Before this module the answer was "nothing", and not as an oversight
## with a bug in it: losing a heart set no state anywhere, so there was no
## fact for any code to act on. The two reports — "you can zoom in and
## shoot at them and they won't do anything" and "when they're being shot
## at they don't seem to care" — are both that one missing fact.
##
## Worth testing rather than eyeballing because it is five inputs and five
## answers, and the cases that matter most are the ones nobody would think
## to go and stand in front of: a bot on its last heart, a bot holding
## only a sword, a bot hit from somewhere it cannot see.

func _respond(hp: int, distance: float, armed: bool, seen: bool,
		nerve := 0.6, age := 0) -> int:
	return BotThreat.respond(age, hp, distance, armed, seen, nerve)

# ---- the answers -------------------------------------------------------

func test_seeing_who_shot_you_means_shooting_back() -> void:
	equal(_respond(5, 20.0, true, true), BotThreat.RETURN_FIRE,
		"armed, healthy, and looking right at them")

func test_being_shot_from_somewhere_you_cannot_see_is_answered() -> void:
	# THE HEADLINE CASE. A player behind cover at sixty blocks used to get
	# no response of any kind. Whatever the bot decides here, it must not
	# be IGNORE.
	not_equal(_respond(5, 60.0, true, false), BotThreat.IGNORE,
		"a sniper has to cost something")

func test_a_bold_bot_goes_looking() -> void:
	equal(_respond(5, 60.0, true, false, 0.8), BotThreat.PUSH,
		"nerve enough to go and find them")

func test_a_nervous_one_gets_behind_something() -> void:
	equal(_respond(5, 60.0, true, false, 0.2), BotThreat.TAKE_COVER,
		"no nerve for it: break the line instead")

func test_badly_hurt_beats_everything_else() -> void:
	# Ordering matters: this has to win over "I can see them and I have a
	# gun", or a bot on one heart stands and trades until it goes down.
	equal(_respond(1, 8.0, true, true), BotThreat.WITHDRAW,
		"one heart left is not a firefight")
	equal(_respond(BotThreat.BREAK_OFF_HP, 8.0, true, true),
		BotThreat.WITHDRAW, "the break-off bar is inclusive")

func test_a_sword_close_by_is_a_charge() -> void:
	equal(_respond(5, 10.0, false, true, 0.9), BotThreat.PUSH,
		"close enough to run at, and the nerve to do it")

func test_a_sword_at_range_is_not() -> void:
	equal(_respond(5, 55.0, false, true, 0.9), BotThreat.WITHDRAW,
		"charging a gun across open ground is a walk to your own knockout")

func test_a_timid_bot_with_a_sword_leaves() -> void:
	equal(_respond(5, 10.0, false, true, 0.1), BotThreat.WITHDRAW,
		"nerve decides, so the same sniper gets different answers")

func test_an_old_alert_is_dropped() -> void:
	equal(_respond(5, 10.0, true, true, 0.6, BotThreat.MEMORY_MS),
		BotThreat.IGNORE, "otherwise a bot walks at one old gunshot all round")
	check(BotThreat.stale(BotThreat.MEMORY_MS), "at the limit it is stale")
	check(not BotThreat.stale(BotThreat.MEMORY_MS - 1), "and not before it")

func test_the_table_is_total() -> void:
	# Every combination returns one of the five and never crashes — the
	# check that catches a future arm added with its conditions
	# overlapping an existing one.
	for hp in range(0, 6):
		for armed in [false, true]:
			for seen in [false, true]:
				for nerve in [0.0, 0.5, 1.0]:
					for distance in [0.0, 12.0, 90.0]:
						var out := _respond(hp, distance, armed, seen, nerve)
						check(out >= BotThreat.IGNORE and out <= BotThreat.WITHDRAW,
							"hp=%d armed=%s seen=%s gave %d"
								% [hp, str(armed), str(seen), out])

# ---- what it means for the rest of the bot ------------------------------

func test_only_the_defensive_answers_want_a_wall() -> void:
	check(BotThreat.wants_cover(BotThreat.TAKE_COVER), "cover is the point of it")
	check(BotThreat.wants_cover(BotThreat.WITHDRAW), "leaving wants a screen too")
	check(not BotThreat.wants_cover(BotThreat.RETURN_FIRE),
		"laying blocks mid-firefight is losing a firefight")
	check(not BotThreat.wants_cover(BotThreat.PUSH), "you cannot build and charge")

func test_being_hit_opens_a_bots_eyes() -> void:
	# The other half of the sniping fix: a fresh alert lets a bot look
	# further than its own eyesight, so it can answer a shot from beyond
	# it. It still needs a clear line to fire, so cover is worth exactly
	# what it was worth before.
	check(BotThreat.sight(22.0, 0) > 55.0,
		"the worst eyesight in the game must still answer a sniper")
	near(BotThreat.sight(22.0, 0), BotThreat.ALERT_SIGHT, 0.001,
		"a fresh alert is worth the full range")

func test_the_widened_range_fades_rather_than_switching_off() -> void:
	var half := BotThreat.sight(22.0, BotThreat.MEMORY_MS / 2)
	between(half, 23.0, BotThreat.ALERT_SIGHT - 1.0,
		"a bot must not go blind mid-fight at the six-second mark")

func test_a_stale_alert_leaves_eyesight_alone() -> void:
	near(BotThreat.sight(30.0, BotThreat.MEMORY_MS + 500), 30.0, 0.001,
		"back to what it can actually see")

func test_sight_is_never_made_worse() -> void:
	near(BotThreat.sight(90.0, 0), 90.0, 0.001,
		"an alert must not blinker a bot that could already see further")

# ---- where it goes ------------------------------------------------------

func test_withdrawing_is_away_from_the_shooter() -> void:
	var me := Vector3(0, 30, 0)
	var them := Vector3(20, 30, 0)
	var go := BotThreat.move_to(BotThreat.WITHDRAW, me, them, 1.0)
	check(go.x < me.x, "away, not towards")
	check(go.distance_to(them) > me.distance_to(them), "and further off")

func test_a_push_does_not_walk_down_the_barrel() -> void:
	# Going straight at the muzzle is the line the shooter is already
	# looking down, and it is how bots came to arrive one at a time over
	# the same ground. It has to come in off to one side.
	var me := Vector3(0, 30, 0)
	var them := Vector3(40, 30, 0)
	var go := BotThreat.move_to(BotThreat.PUSH, me, them, 1.0)
	check(absf(go.z) > 4.0, "a push should go wide: %s" % str(go))
	check(go.distance_to(them) < me.distance_to(them), "but still close in")

func test_two_bots_flank_opposite_ways() -> void:
	var me := Vector3(0, 30, 0)
	var them := Vector3(40, 30, 0)
	var left := BotThreat.move_to(BotThreat.PUSH, me, them, 1.0)
	var right := BotThreat.move_to(BotThreat.PUSH, me, them, -1.0)
	check(left.z * right.z < 0.0, "the lane is what splits them up")

func test_cover_is_sideways_not_a_sprint() -> void:
	var me := Vector3(0, 30, 0)
	var them := Vector3(30, 30, 0)
	var go := BotThreat.move_to(BotThreat.TAKE_COVER, me, them, 1.0)
	check(absf(go.z) > absf(go.x), "the aim is to break the line, not to run")

func test_a_threat_on_top_of_you_still_gives_a_direction() -> void:
	# Same point, so the direction is a normalise-by-zero. It must not
	# return NaN, which spreads silently through every position after it.
	var me := Vector3(4, 30, 4)
	var go := BotThreat.move_to(BotThreat.WITHDRAW, me, me, 1.0)
	check(not is_nan(go.x) and not is_nan(go.z), "no NaN out of a zero length")
	check(go.distance_to(me) > 1.0, "and it still goes somewhere")
