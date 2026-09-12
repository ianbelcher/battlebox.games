extends TestCase
## King of the Hill's map: one dome around the origin, high in the middle
## and a shore near the edge — never a second peak to fight over instead.

func test_the_summit_is_at_the_origin() -> void:
	var gen := WorldGen.new(11, "mountain", 250)
	var summit := gen.height_at(0, 0)
	check(summit > WorldGen.SEA_LEVEL + 30, "a real peak, not a bump: %d" % summit)
	check(summit < WorldGen.CHUNK_H - 6, "short of the clamp, on purpose: %d" % summit)

func test_height_falls_away_from_the_summit() -> void:
	var gen := WorldGen.new(11, "mountain", 250)
	var summit := gen.height_at(0, 0)
	var prev := summit
	# Averaged over several bearings so one noisy sample near a ridge line
	# cannot fail the test the shape itself would pass.
	for dist in [20, 40, 60, 80, 100]:
		var total := 0
		var samples := 8
		for i in samples:
			var a := float(i) / float(samples) * TAU
			total += gen.height_at(int(cos(a) * dist), int(sin(a) * dist))
		var avg := total / samples
		check(avg < prev, "height at %d is lower than closer in (%d < %d)" % [dist, avg, prev])
		prev = avg

func test_there_is_a_shore_near_the_edge() -> void:
	var gen := WorldGen.new(11, "mountain", 250)
	var edge := gen.height_at(120, 0)
	check(edge <= WorldGen.SEA_LEVEL + 6, "the foot of the mountain is near sea level: %d" % edge)
