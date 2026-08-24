extends TestCase
## Fitting twenty teams into a panel built for four.

func test_a_normal_game_does_not_shrink() -> void:
	for teams in range(1, 7):
		equal(TeamBoard.font_px(teams, 14), 14,
			"%d teams still reads at full size" % teams)

func test_a_long_board_shrinks() -> void:
	check(TeamBoard.font_px(20, 14) < 14, "twenty teams is smaller than four")

func test_but_never_past_being_readable() -> void:
	for teams in range(1, 200):
		check(TeamBoard.font_px(teams, 14) >= TeamBoard.MIN_PX,
			"%d teams still readable" % teams)

func test_shrinking_never_goes_back_up() -> void:
	var last := 99
	for teams in range(1, 60):
		var px := TeamBoard.font_px(teams, 14)
		check(px <= last, "more teams is never bigger text (%d)" % teams)
		last = px

func test_everything_fits_when_it_fits() -> void:
	equal(TeamBoard.visible_rows([0, 1, 2], 1, 8), [0, 1, 2], "no trimming needed")

func test_the_leaders_are_kept() -> void:
	equal(TeamBoard.visible_rows([3, 1, 0, 2], 3, 2), [3, 1], "top two by rank")

## THE ROW THIS EXISTS FOR. Your team is bottom of a field of twenty and
## the board only has room for five — yours is still one of them, because
## it is the line you look for first.
func test_your_own_team_is_never_dropped() -> void:
	var ranked := range(0, 20)
	var shown := TeamBoard.visible_rows(ranked, 19, 5)
	equal(shown.size(), 5, "still only five rows")
	check(shown.has(19), "and one of them is yours")

func test_and_it_displaces_rather_than_overflows() -> void:
	var shown := TeamBoard.visible_rows(range(0, 10), 9, 3)
	equal(shown.size(), 3, "the cap is a cap")
	check(shown.has(0) and shown.has(1), "the leaders survive")

func test_no_team_of_your_own_is_fine() -> void:
	equal(TeamBoard.visible_rows([0, 1, 2, 3], -1, 2), [0, 1], "just the leaders")

func test_the_missing_are_counted() -> void:
	equal(TeamBoard.hidden(20, 5), 15, "fifteen not shown")
	equal(TeamBoard.hidden(4, 4), 0, "nothing missing")

func test_room_for_at_least_one_row() -> void:
	equal(TeamBoard.row_cap(0.0, 14), 1, "never an empty board")
	equal(TeamBoard.row_cap(140.0, 14), 10, "ten rows in ten rows' worth")
