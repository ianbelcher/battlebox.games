class_name BotThreat
## WHAT A COMPUTER PLAYER DOES ABOUT BEING SHOT AT.
##
## Until now: nothing. There was no such thing as being shot at. A bot
## looked for enemies inside its own eyesight, and if it found one with a
## clear line it fired back; a hit that landed on it changed no state
## anywhere, because `MatchDirector.hurt` took hearts off and told nobody.
##
## Two complaints fall straight out of that, and they are the same
## complaint:
##
##   "I can zoom in and shoot at them and they won't do anything." Of
##   course not — eyesight tops out at fifty-five blocks for the best of
##   them and twenty-two for the worst, and a scoped shot comes from
##   further than that. The bot is not ignoring you. It has no idea you
##   exist, and nothing that happens to it will ever tell it.
##
##   "When they're being shot at they don't seem to care." They cannot.
##   Losing a heart is not an event a bot can observe.
##
## So a hit — and a shot that lands near enough to hear — now becomes an
## ALERT: a place, a time, and whether the shooter can be seen from here.
## This module is what an alert MEANS. It takes numbers and returns one of
## five things to do, and it is separate from the director for the usual
## reason: "does a bot on two hearts with no gun ever charge a sniper?" is
## a question about a truth table, and a truth table can be checked
## without playing a round and watching.
##
## The five answers, and why each one exists:
##
##   RETURN_FIRE   you can see them and you have something to shoot with.
##                 Stand and trade. Anything cleverer than this at close
##                 range is a bot that dies while being clever.
##   PUSH          you cannot see them, or you have only a sword. Go at
##                 where the shot came from. This is what makes sniping
##                 from a hilltop cost something: the ones you miss come
##                 looking.
##   TAKE_COVER    you are being hit from somewhere you cannot answer and
##                 you are not in a state to charge it. Break the line —
##                 and, since everyone here carries blocks, build one.
##   WITHDRAW      badly hurt. Get out of it entirely; a knocked-out bot
##                 helps nobody, and there is loot to be found.
##   IGNORE        the alert is old. Everything above expires, or a bot
##                 spends the rest of the round walking towards a place
##                 somebody shot at it from once.

enum { IGNORE, RETURN_FIRE, PUSH, TAKE_COVER, WITHDRAW }

## HOW LONG AN ALERT IS WORTH ACTING ON.
##
## Deliberately longer than the four seconds a bot remembers somebody it
## merely SAW, and for a reason: being hit is better information than
## catching sight of somebody. It means there is definitely an enemy, it
## is definitely shooting, and it is definitely in range of you. Six
## seconds is long enough to cross the distance a rifle shot came from and
## short enough that the round moves on.
const MEMORY_MS := 6000

## HOW FAR AN ALERTED BOT CAN SEE.
##
## Being shot tells you roughly where somebody is whether or not you had
## noticed them, so for as long as the alert lasts the bot's eyes open to
## this — well past the best natural eyesight in the game. It still has to
## have a CLEAR LINE to fire, so cover and sneaking are worth exactly what
## they were worth before; what changes is that a bot picked off from
## sixty blocks now shoots back instead of standing there.
const ALERT_SIGHT := 72.0

## How near a shot has to land to count as being shot at, when it misses.
## Wide enough that walking your fire onto somebody warns them, tight
## enough that a firefight forty blocks away is not everybody's business.
const NEAR_MISS := 7.0

## Under this many hearts a bot stops trading and leaves. Two, out of the
## five a match starts with: the same bar the rest of the director uses
## for "too hurt to go and rescue somebody".
const BREAK_OFF_HP := 2

## A sword is only an answer to a gun if the gun is close enough to run
## at. Past this, charging one across open ground is a walk to your own
## knockout, and the bot goes and finds a crate instead.
const RUSH_RANGE := 18.0

## …and even inside it, only the ones with the nerve for it. A rookie
## breaks off, a deadly one comes at you. Same `nerve` the hunting code
## uses, so a bot behaves like itself in both.
const RUSH_NERVE := 0.45

## The nerve it takes to go LOOKING for somebody you cannot see, rather
## than getting behind something and waiting.
const SEEK_NERVE := 0.5

static func stale(age_ms: int) -> bool:
	return age_ms >= MEMORY_MS

## What to do about it. `armed` means holding something that shoots —
## a sword is not one. `seen` means there is a clear line to the shooter
## RIGHT NOW, which is the same test the shot itself uses.
##
## Ordered hardest-first: how hurt you are beats what you are holding,
## which beats whether you can see them. Reading it in that order is the
## whole rule.
static func respond(age_ms: int, hp: int, distance: float, armed: bool,
		seen: bool, nerve: float) -> int:
	if stale(age_ms):
		return IGNORE
	if hp <= BREAK_OFF_HP:
		return WITHDRAW
	if not armed:
		# Nothing to shoot back with. Close the distance or leave; the one
		# thing that is never right is standing in the open holding a
		# sword while somebody shoots at you, which is what a bot with no
		# alert behaviour does by default.
		if distance <= RUSH_RANGE and nerve >= RUSH_NERVE:
			return PUSH
		return WITHDRAW
	if seen:
		return RETURN_FIRE
	# Armed, hit, and cannot see who did it: either go and find them or
	# get behind something. Nerve decides, so the same sniper gets
	# different answers from different bots — which is the point of
	# rolling a personality for each one.
	return PUSH if nerve >= SEEK_NERVE else TAKE_COVER

## Is this the sort of answer that wants a block laying between you and
## them? Only the two that are about not being shot; a bot laying blocks
## while it is winning a firefight is a bot losing one.
static func wants_cover(action: int) -> bool:
	return action == TAKE_COVER or action == WITHDRAW

## HOW FAR TO SEE, given an alert of this age. The widened range decays to
## the bot's own eyesight rather than switching off, so a bot does not go
## blind mid-fight at the six-second mark.
static func sight(natural: float, age_ms: int) -> float:
	if stale(age_ms):
		return natural
	var fade := 1.0 - float(age_ms) / float(MEMORY_MS)
	return maxf(natural, lerpf(natural, ALERT_SIGHT, fade))

## WHERE TO ACTUALLY WALK, for the two answers that are a movement.
##
## PUSH does not walk down the line the shot came along — that is the line
## the shooter is already looking at, and it is how bots came to arrive
## one at a time over the same ground. It goes wide and comes at the
## threat from a quarter-turn off, with the side chosen from the bot's own
## id so two of them go opposite ways.
##
## TAKE_COVER and WITHDRAW go the other way: directly away, which is the
## shortest route out of somebody's sight line.
static func move_to(action: int, me: Vector3, threat: Vector3,
		lane: float) -> Vector3:
	var out := Vector3(me.x - threat.x, 0.0, me.z - threat.z)
	if out.length() < 0.001:
		out = Vector3(1.0, 0.0, 0.0)
	out = out.normalized()
	match action:
		WITHDRAW:
			return me + out * 22.0
		TAKE_COVER:
			# Sideways and back: straight back is a longer walk in the
			# open, and the aim is to put something between you rather
			# than to be further away.
			var side := Vector3(-out.z, 0.0, out.x) * lane
			return me + out * 6.0 + side * 8.0
		PUSH:
			var flank := Vector3(-out.z, 0.0, out.x) * lane
			return threat + out * 4.0 + flank * 9.0
	return me
