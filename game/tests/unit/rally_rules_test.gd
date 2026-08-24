extends TestCase
## Who comes to pick you up, and who stays out of it.

const REACH := 20.0

func _at(team: int, x: float, downed := false, out := false) -> Dictionary:
	return {"team": team, "pos": Vector3(x, 0, 0), "downed": downed, "out": out}

func test_walks_to_the_nearest_team_mate() -> void:
	var others := [_at(1, 12.0), _at(1, 4.0), _at(1, 9.0)]
	equal(RallyRules.pick_up_at(1, Vector3.ZERO, others, REACH), 1,
		"the closest of your own")

## THE BUG THIS FILE EXISTS FOR. An enemy standing on top of you must
## never be chosen over a team-mate further off — the inverted test picked
## exactly this case, and a knocked-out player walked at whoever had just
## put them down.
func test_never_walks_to_an_enemy() -> void:
	var others := [_at(2, 1.0), _at(1, 15.0)]
	equal(RallyRules.pick_up_at(1, Vector3.ZERO, others, REACH), 1,
		"the far team-mate, not the enemy at your feet")

func test_an_enemy_alone_is_nobody_coming() -> void:
	equal(RallyRules.pick_up_at(1, Vector3.ZERO, [_at(2, 2.0)], REACH), -1,
		"a field of enemies is not help")

func test_someone_on_the_floor_cannot_lift_you() -> void:
	var others := [_at(1, 3.0, true), _at(1, 11.0)]
	equal(RallyRules.pick_up_at(1, Vector3.ZERO, others, REACH), 1,
		"walk past the body to the one still standing")

func test_someone_out_of_the_round_cannot_either() -> void:
	var others := [_at(1, 3.0, false, true), _at(1, 11.0)]
	equal(RallyRules.pick_up_at(1, Vector3.ZERO, others, REACH), 1,
		"out is out — they cannot pick anyone up")

func test_out_of_reach_is_nobody_coming() -> void:
	equal(RallyRules.pick_up_at(1, Vector3.ZERO, [_at(1, 40.0)], REACH), -1,
		"too far to be help")

func test_empty_field() -> void:
	equal(RallyRules.pick_up_at(1, Vector3.ZERO, [], REACH), -1, "nobody at all")

## One pair of hands. The closest goes; everybody else keeps playing.
func test_the_closest_takes_the_body() -> void:
	check(RallyRules.mine_to_take(5.0, [9.0, 12.0]), "nearest of three goes")

func test_and_the_others_stay_in_the_fight() -> void:
	check(not RallyRules.mine_to_take(9.0, [5.0, 12.0]), "somebody is closer")

func test_alone_it_is_always_yours() -> void:
	check(RallyRules.mine_to_take(18.0, []), "no rivals, so it is yours")

func test_a_tie_does_not_leave_the_body_on_the_floor() -> void:
	# Equal distances must not BOTH stand down, or nobody ever goes.
	check(RallyRules.mine_to_take(7.0, [7.0]), "ties go, rather than defer")
