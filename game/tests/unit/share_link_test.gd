extends TestCase
## The link that gets a friend into your private game.
##
## This is tested because it is the ONLY way anybody else reaches a
## private room, and because getting it wrong fails silently: a link that
## drops the code lands you in the always-on world, which is indis-
## tinguishable from a private game that simply has nobody in it yet.

func test_a_private_game_carries_its_code() -> void:
	equal(Room.link_for("https://battlebox.games", "brave-otter"),
		"https://battlebox.games/?room=brave-otter",
		"the code is what makes the link worth sending")

## main.gd reads `?room=` on launch. If these two ever disagree the link
## opens the wrong game, so the parameter name is asserted literally here
## rather than shared through a constant nobody would look at.
func test_the_parameter_is_the_one_the_game_reads_on_launch() -> void:
	check(Room.link_for("https://x.example", "keen-badger").contains("?room="),
		"main.gd parses ?room= — this must spell it the same way")

func test_the_house_game_is_just_the_address() -> void:
	equal(Room.link_for("https://battlebox.games", Room.HOUSE_CODE),
		"https://battlebox.games/",
		"the default game should be the plain address people already have")
	equal(Room.link_for("https://battlebox.games", ""),
		"https://battlebox.games/",
		"and so should no code at all")

func test_a_trailing_slash_does_not_double_up() -> void:
	equal(Room.link_for("https://battlebox.games/", "brave-otter"),
		"https://battlebox.games/?room=brave-otter",
		"origins arrive with and without one")

func test_off_the_web_there_is_no_link() -> void:
	# A desktop or LAN build has no address to hand anybody. Empty means
	# "show the code instead", and the callers check for it.
	equal(Room.link_for("", "brave-otter"), "", "no origin, no link")

func test_a_code_is_matched_the_way_it_is_typed_in() -> void:
	# The join field lower-cases what it is given, so a link generated
	# from a differently-cased code has to agree or it will not be found.
	equal(Room.link_for("https://x.example", "Brave-Otter"),
		"https://x.example/?room=brave-otter",
		"same room, however it was capitalised")

func test_a_hostile_code_cannot_break_out_of_the_parameter() -> void:
	var link := Room.link_for("https://x.example", "a&b=c")
	check(not link.contains("&b="),
		"a room name is not allowed to add query parameters: %s" % link)
