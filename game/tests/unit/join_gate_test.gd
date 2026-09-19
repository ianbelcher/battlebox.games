extends TestCase
## Nobody gets a seat for a press they made to do something else.
##
## The regression this guards: the keyboard that set the game up — Play
## on the lobby screen, Space on a world-menu button — sat itself down as
## a player, and had to be kicked before a child's controller could join.

const KB := "dev:kb:0"
const PAD := "dev:pad:0"

func test_a_key_held_on_arrival_does_not_join() -> void:
	var gate := JoinGate.new()
	# Space was pressed on Play and is still down when the world appears.
	check(not gate.press_counts(KB, true, false), "the Play press is not a join")
	check(not gate.press_counts(KB, true, false), "nor while it stays held")
	check(not gate.press_counts(KB, false, false), "letting go is not a join")
	check(gate.press_counts(KB, true, false), "a fresh press joins")

func test_a_fresh_press_after_arrival_joins() -> void:
	var gate := JoinGate.new()
	check(not gate.press_counts(PAD, false, false), "resting pad")
	check(gate.press_counts(PAD, true, false), "A pressed on the join screen joins")

func test_arriving_again_forgets_what_was_seen_before() -> void:
	var gate := JoinGate.new()
	gate.press_counts(KB, false, false)
	# A reconnect: the world comes up again with Space down.
	gate.hold_all()
	check(not gate.press_counts(KB, true, false), "held over the arrival")

func test_presses_inside_a_menu_never_join() -> void:
	var gate := JoinGate.new()
	gate.press_counts(KB, false, false)
	check(not gate.press_counts(KB, true, true), "Space on a menu button")
	# The menu shuts while Space is still down.
	gate.hold_all()
	check(not gate.press_counts(KB, true, false), "still the menu press")
	gate.press_counts(KB, false, false)
	check(gate.press_counts(KB, true, false), "pressed again, on purpose")

func test_a_menu_closing_on_the_press_itself_does_not_join() -> void:
	var gate := JoinGate.new()
	gate.press_counts(KB, false, true)
	# Space goes down and shuts the menu in the same frame; the poll sees
	# the menu gone and the key down, and main.gd lifts the gate.
	gate.hold_all()
	check(not gate.press_counts(KB, true, false), "the closing press is not a join")

func test_one_device_held_does_not_block_another() -> void:
	var gate := JoinGate.new()
	gate.press_counts(KB, true, false)  # held over from the lobby
	gate.press_counts(PAD, false, false)
	check(gate.press_counts(PAD, true, false), "the pad still joins")
	check(not gate.press_counts(KB, true, false), "the keyboard still does not")
