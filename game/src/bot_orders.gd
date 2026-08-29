class_name BotOrders
## WHAT A TEAM OF COMPUTER PLAYERS DECIDES TOGETHER: how many stay home,
## and which enemy flag the rest go for.
##
## The old answer to both was arithmetic on a seat number. Keepers were a
## fixed share of the team — a third in capture the flag, a half in last
## flag standing — and raiders were dealt round-robin across the standing
## flags. Neither took the slightest notice of what was actually
## happening, and that is what both of the complaints about it are:
##
##   A GUARD THAT DOES NOT ANSWER THE DOOR. Six defenders sat on a flag
##   nobody was walking towards while, two bases away, three of their own
##   side were being taken apart by eight. The share was right on paper
##   and wrong on the field, because the field had a shape and the share
##   could not see it.
##
##   A TEAM THAT SCATTERS. Round-robin means a side of nine with three
##   enemy flags sends three at each — every attack outnumbered by every
##   defence, everywhere, all round. From the outside that is "they just
##   run off in random directions", and it is exactly what dealing cards
##   does: it spreads effort perfectly evenly, which is the one thing you
##   never want to do with it.
##
## So both questions are answered from what the team can actually SEE —
## the contact reports its members share (BotDirector keeps them) — rather
## than from a ratio:
##
##   HOW MANY STAY: the base share, plus one for every enemy spotted near
##   our own flag, minus the guard nobody needs when the doorstep has been
##   quiet. A side under attack turns and fights; a side nobody is
##   bothering goes and takes something.
##
##   WHERE THE REST GO: the flag your team-mates are already going to,
##   unless it is a long way further than one nobody has picked. Numbers
##   win fights, and a bot that can see where its side is heading and go
##   with them is the difference between nine attacks of one and three
##   attacks of three.
##
## EVERYTHING HERE IS STATIC AND PURE — no world, no roster, no autoloads
## — for the same reason BotSquads is: the questions worth asking of it
## ("does a team under attack actually reinforce?", "does a side ever
## concentrate?") are questions about numbers, and a `--script` test run
## has no autoloads to give it anything else.

## How much closer a flag FEELS for each team-mate already going there,
## in blocks. This is the whole of "go with them", and its size is a
## balance decision: at 22 a bot will walk sixty-odd blocks out of its way
## to arrive with three others rather than alone, which is the right trade
## — three together take a base, one alone feeds it.
const FRIEND_PULL := 22.0

## …and it stops counting past this many. Without a ceiling the pull grows
## without limit and the whole side ends up in one column walking at one
## flag, which is the scatter problem again with the sign flipped.
const FRIEND_PULL_CAP := 3

## The most attackers one flag draws before the rest look elsewhere, over
## and above its even share. Two is enough to make a real surge visible
## and few enough that every standing flag still gets somebody — which is
## an invariant of this mode and not a nicety: a flag nobody ever walks
## towards is a team that cannot lose.
const SURGE_BONUS := 2

## …and never fewer than a squad, however many flags there are. A "fair
## share" of one is how you get nine attacks of one again.
const SURGE_MIN := 3

## How far from our own flag an enemy has to be before they stop being our
## problem. Roughly the range the guns reach across a base.
const HOME_WATCH := 26.0

## The most the guard is ever reinforced by what is at the door. Without a
## cap a busy doorstep pulls the entire side home and nobody attacks
## anything, which is the huddle this whole module exists to prevent.
const RALLY_HOME_CAP := 4

## HOW MANY OF A TEAM MIND ITS OWN FLAG.
##
## `base` is the ratio SiegeRoles would have given — the mode's default
## posture — and everything here is a correction to it from what the team
## has seen.
##
##   NOTHING LEFT TO TAKE: everybody home. Not a huddle: there is
##   genuinely nothing else to do, and in last flag standing holding is
##   how that position is won.
##
##   ENEMIES AT THE DOOR: one more defender per enemy spotted, capped, and
##   never the whole side — somebody is always still out, because a team
##   that recalls everyone the moment it is touched can be pinned by one
##   attacker for the whole round.
##
##   A QUIET DOORSTEP: thin the guard by one, floor of one. This is the
##   half of it that stops "they all huddle": defence is the default
##   posture in a siege, so without something actively spending it, the
##   default is all anyone ever does.
##
## The two invariants worth stating out loud, because both have been got
## wrong here before and neither is visible without playing a round:
## somebody always stays while we still have a flag, and somebody always
## goes while there is still a flag to take.
## THE QUIET-DOORSTEP DISCOUNT DOES NOT APPLY TO A SIEGE.
##
## Thinning the guard when nobody is at the door is right in capture the
## flag, where losing your flag costs a point and the round carries on. In
## last flag standing it costs you the ROUND — there is no coming back —
## so the mode's own share (HoldoutRules) is already the considered answer
## and second-guessing it downward every quiet moment is how a siege stops
## being one. It took a defender off every team in the mode that can least
## afford it.
static func keepers(team_size: int, base: int, home_threat: int,
		targets_left: int, siege := false) -> int:
	if team_size <= 0:
		return 0
	if targets_left <= 0:
		return team_size
	var want := clampi(base, 0, team_size)
	if home_threat > 0:
		want += mini(home_threat, RALLY_HOME_CAP)
	elif want > 1 and not siege:
		want -= 1
	# Somebody stays, somebody goes. In that order: with a team of one
	# there is nobody to do both, and going is worth more than staying
	# because a flag you never attack is a round you cannot win.
	want = clampi(want, 1, team_size - 1)
	return maxi(want, 0) if team_size > 1 else 0

## The other side of the same coin, so a caller never has to subtract by
## hand and get it the wrong way round.
static func attackers(team_size: int, base: int, home_threat: int,
		targets_left: int, siege := false) -> int:
	return maxi(0, team_size
		- keepers(team_size, base, home_threat, targets_left, siege))

## HOW MANY ATTACKERS ONE FLAG IS ALLOWED TO PULL.
##
## An even share plus a surge. The surge is the point — it is what lets a
## side gang up on one base instead of dividing itself into losing halves
## — and the share is what stops the gang becoming the whole team, so the
## flags nobody chose still get visited.
static func surge_cap(attacker_count: int, targets: int) -> int:
	if targets <= 1:
		return maxi(attacker_count, 1)
	var share := int(ceil(float(attacker_count) / float(targets)))
	return maxi(SURGE_MIN, share + SURGE_BONUS)

## ONE SCOUT PER FLAG BEFORE ANYBODY MASSES.
##
## Concentration is the whole point of `pick_target`, and taken on its own
## it breaks a rule this game has been bitten by before: every standing
## enemy flag has to have SOMEBODY walking at it. A flag nobody ever
## approaches belongs to a team that cannot lose, and five of those is a
## round where nothing happens. Left to scoring alone it happens easily —
## twelve attackers over three flags came out six, six, and none.
##
## So the first attackers dealt out are scouts, one to each standing flag,
## by raider index. It is the old round-robin, kept for exactly as long as
## it takes to cover the board, and everybody after that is free to join
## whoever they like. One bot walking at a base is not an attack, but it
## is a pair of eyes, and it is what stops a side being ignored.
##
## Returns the index of the flag this attacker scouts, or -1 for "not a
## scout, choose for yourself".
static func scout_target(raider_index: int, targets: int) -> int:
	return raider_index if raider_index >= 0 and raider_index < targets else -1

## WHICH FLAG TO GO FOR. Returns an index into `options`, or -1 when there
## is nothing to attack.
##
## Each option is {"dist": blocks away, "friends": team-mates already
## committed to it}. Scored in blocks, lowest wins, so the whole rule
## reads as one sentence: a flag is worth walking to if it is near, and
## every team-mate already walking that way makes it feel FRIEND_PULL
## blocks nearer.
##
## Options at or over the cap are passed over first — that is the surge
## limit — and only if EVERY option is full does it fall back to the
## emptiest, so a bot always has somewhere to go rather than standing
## still because the arithmetic ran out. Standing still was the old
## failure mode when a target came back -1 and there is no reason to
## reintroduce it here.
static func pick_target(options: Array, cap: int) -> int:
	if options.is_empty():
		return -1
	var best := -1
	var best_score := INF
	for i in options.size():
		var option: Dictionary = options[i]
		if int(option.get("friends", 0)) >= cap:
			continue
		var score := _score(option)
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		return best
	# Everything is full: take the least crowded, nearest first among
	# equals.
	var fewest := INF
	for i in options.size():
		var option: Dictionary = options[i]
		var rank := float(int(option.get("friends", 0))) * 1000.0 \
			+ float(option.get("dist", 0.0))
		if rank < fewest:
			fewest = rank
			best = i
	return best

static func _score(option: Dictionary) -> float:
	var friends := mini(int(option.get("friends", 0)), FRIEND_PULL_CAP)
	return float(option.get("dist", 0.0)) - float(friends) * FRIEND_PULL

## IS THIS BOT ALLOWED TO CHANGE ITS MIND YET?
##
## A choice made from what everybody else has chosen is a choice that can
## oscillate: I go where you are going, you notice I left and follow, and
## the pair of us swap bases for the rest of the round. So a target is
## COMMITTED for a while once taken, and only re-opened when it stops
## existing or the commitment runs out.
##
## Long enough to actually arrive somewhere. A raid across a 250-block map
## at a running pace is the better part of a minute, and re-deciding
## half-way is the same as never deciding.
const COMMIT_MS := 30_000

static func may_rethink(age_ms: int, still_standing: bool) -> bool:
	return not still_standing or age_ms >= COMMIT_MS
