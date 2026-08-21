extends TestCase
## The character system: what a style means, and that every combination of
## the mix-and-match parts actually builds.

func test_normalize_fills_in_a_missing_outfit() -> void:
	var style := AvatarFactory.normalize_style({"who": "c"})
	equal(style.who, "c", "the chosen character survives normalizing")
	equal(style.fit, "c", "no outfit means wearing your own clothes")

func test_normalize_keeps_a_chosen_outfit() -> void:
	var style := AvatarFactory.normalize_style({"who": "c", "fit": "m"})
	equal(style.who, "c", "character kept")
	equal(style.fit, "m", "outfit kept")

func test_unknown_characters_map_somewhere_real_and_stay_there() -> void:
	# Styles saved by older builds named characters that no longer exist
	# ("p12" was a Little Person, {"body": 3, ...} was the hand-built rig).
	# Both have to land on a real character, and land on the SAME one every
	# time, or a returning player is reshuffled on every join.
	for legacy: Variant in [{"who": "p12"}, {"body": 3, "shirt": 7, "hat": 2},
			{"who": "zzz"}, {}]:
		var first := AvatarFactory.normalize_style(legacy)
		var second := AvatarFactory.normalize_style(legacy)
		has(AvatarFactory.characters(), first.who,
			"%s maps to a real character" % [legacy])
		equal(second.who, first.who, "%s maps to the same one twice" % [legacy])

func test_junk_does_not_crash_the_avatar() -> void:
	for junk: Variant in [null, 7, "nonsense", []]:
		var style := AvatarFactory.normalize_style(junk)
		has(AvatarFactory.characters(), style.who,
			"%s still yields a real character" % [junk])

func test_every_character_has_a_model_and_a_portrait() -> void:
	for who: String in AvatarFactory.characters():
		check(ResourceLoader.exists(AvatarFactory.model_of(who)),
			"character %s has a model at %s" % [who, AvatarFactory.model_of(who)])
		check(ResourceLoader.exists(AvatarFactory.portrait_of(who)),
			"character %s has a portrait" % who)

func test_every_character_ships_all_six_parts() -> void:
	# The whole mix-and-match scheme rests on this: same six nodes, same
	# names, in every one of them. A pack update that renamed or dropped
	# one would break outfits silently, and this is what would catch it.
	for who: String in AvatarFactory.characters():
		var scene: PackedScene = load(AvatarFactory.model_of(who))
		var probe: Node3D = scene.instantiate()
		for part: String in AvatarFactory.SKIN_PARTS + AvatarFactory.FIT_PARTS:
			var node := probe.find_child(part, true, false) as MeshInstance3D
			check(node != null and node.mesh != null,
				"character %s has a '%s' mesh" % [who, part])
		check(probe.find_child("AnimationPlayer", true, false) != null,
			"character %s has an AnimationPlayer" % who)
		probe.free()

func test_held_items_have_an_arm_to_hang_from() -> void:
	# player.gd finds the hand by this exact node name. Losing it means
	# every held tool silently vanishes.
	var avatar := AvatarFactory.build_character({"who": "a", "fit": "a"})
	check(avatar.find_child("arm-right", true, false) != null,
		"the built avatar exposes arm-right")
	avatar.free()

func test_all_324_combinations_build() -> void:
	var built := 0
	for who: String in AvatarFactory.characters():
		for fit: String in AvatarFactory.outfits():
			var avatar := AvatarFactory.build_character({"who": who, "fit": fit})
			check(avatar != null, "%s wearing %s builds" % [who, fit])
			if avatar == null:
				continue
			check(avatar.has_meta("ap"),
				"%s wearing %s animates itself" % [who, fit])
			built += 1
			avatar.free()
	equal(built, 18 * 18, "every character wears every outfit")

func test_an_outfit_actually_changes_the_body_and_leaves_the_face_alone() -> void:
	var plain := AvatarFactory.build_character({"who": "a", "fit": "a"})
	var dressed := AvatarFactory.build_character({"who": "a", "fit": "k"})
	for part: String in AvatarFactory.FIT_PARTS:
		var before := (plain.find_child(part, true, false) as MeshInstance3D).mesh
		var after := (dressed.find_child(part, true, false) as MeshInstance3D).mesh
		not_equal(after, before, "'%s' comes from the outfit" % part)
	for part: String in AvatarFactory.SKIN_PARTS:
		var before := (plain.find_child(part, true, false) as MeshInstance3D).mesh
		var after := (dressed.find_child(part, true, false) as MeshInstance3D).mesh
		equal(after, before, "'%s' is still the wearer's own" % part)
	plain.free()
	dressed.free()
