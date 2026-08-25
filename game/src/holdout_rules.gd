class_name HoldoutRules
## LAST FLAG STANDING: capture the flag, except losing your flag puts your
## whole team out of the round.
##
## It turns capture the flag inside out. In capture the flag your own base
## is a place you keep coming back to; here it is the only thing you have,
## and a single successful raid ends you. That makes defending worth more
## than attacking, which is the point of it — a game about building
## something you can hold rather than about running back and forth.
##
## THE ROUND ENDS when one team is left, or when the clock runs out. Both
## are ordinary outcomes: a stalemate between two well-dug-in teams is a
## real result and not a failure, so it scores.
##
## SIX POINTS ARE SHARED between whoever is still standing, and only if
## there are few enough of them to make it an achievement:
##
##   1 team left   6 each     they won it
##   2 teams       3 each     they both held
##   3 teams       2 each     a crowd, but everyone dug in
##   4 or more     0 each     nobody was really under threat
##
## Six because it divides by one, two and three — which is what makes
## "share the round" mean equal shares rather than remainders.
##
## Pure and on its own so the table can be checked. A `--script` run has
## no autoloads, so anything needing the world cannot be tested at all.

const ROUND_POINTS := 6

## How long a round runs before the clock decides it, in minutes. Long
## enough to build something worth holding.
## The default round length. It is a SETTING now — see
## WorldNode.holdout_minutes — and this is what a fresh world starts on.
const ROUND_MINUTES := 10.0

## What the grown-up can choose, in minutes. "Unlimited" is an hour: long
## enough that no round of this reaches it, and a real number so the clock
## on screen, the scoring at the whistle and the last push all keep
## working rather than needing a special case each.
const LENGTHS := [2, 5, 10, 60]
const UNLIMITED := 60

static func length_label(minutes: int) -> String:
	return "Unlimited" if minutes >= UNLIMITED else "%d min" % minutes

## What each surviving team scores. Zero when too many survived for it to
## have been much of a siege.
static func share(survivors: int) -> int:
	if survivors <= 0:
		return 0
	if survivors > 3:
		return 0
	return ROUND_POINTS / survivors

## HOW MUCH OF A TEAM STAYS HOME. Two thirds of it: this mode is about
## holding a base, and a team that empties out to go raiding has already
## lost, because there is no coming back from losing your flag.
##
## NEVER FEWER THAN A PAIR GOING OUT, and that rule is the difference
## between a game and a stalemate. The first version kept three quarters
## home, which for a team of four is three defenders and ONE attacker —
## and one attacker against a dug-in base is not an attack, it is a
## delivery. Watched it: five teams, four minutes, not a single flag
## taken, and under the scoring table five survivors share nothing. A
## round that cannot be won is worth exactly as much as it sounds.
##
## Two is also the smallest group the squad logic will advance with (see
## BotSquads.ready_to_push), so it is the smallest number that attacks at
## all rather than milling about at a rally point.
##
## Still far more defensive than capture the flag, which posts at most two
## keepers however big the team is: at ten a side that is two against this
## mode's six.
## AND A TEAM OF ONE GOES OUT. This returned `team_size` — so a lone
## player was a lone KEEPER, with nobody to attack with and nobody to
## attack for. Five one-player teams is therefore five bases nobody ever
## walks towards: a measured round of it took not one flag, ended with all
## five holding, and paid every one of them nothing. Guarding a base that
## is not under threat is not a strategy, it is a way of not playing.
## HALF, NOT TWO THIRDS. Two thirds was asked for — this mode is about
## holding a base — and measured on the field it is not a defensive game,
## it is no game: a team of five put three on the wall and sent two, and
## two attackers against three defenders behind a wall with a roof on it
## never take anything. Nothing then happens for ten minutes, every side
## sits on its own flag, and it reads exactly as "all of the bots just
## huddle around the flag and don't do anything" — which is what it is.
##
## Half still leaves a real guard, and it is still far more defensive than
## capture the flag, which posts at most two keepers however big the team.
static func keepers(team_size: int) -> int:
	if team_size <= 1:
		return 0
	if team_size == 2:
		return 1          # one minds the flag, one goes out
	return clampi(team_size / 2, 1, team_size - 2)

## The last stretch of a round, when the guard thins out — a fifth of it,
## but never more than two minutes.
##
## IN SECONDS AS WELL AS A FRACTION, because the round length is a setting
## now and a fraction alone breaks at both ends of it. A fifth of an hour
## is twelve minutes of "last push", which is most of the round; a fifth
## of two minutes is twenty-four seconds, which is right. So: a fifth,
## capped.
const PUSH_FRACTION := 0.2
const PUSH_SECONDS := 120.0

## …and however long the round is set to, a siege that has gone on this
## long opens up anyway. Two dug-in sides will not finish each other off,
## and on an unlimited round there is no whistle to make them: without
## this, "unlimited" means "forever" rather than "as long as it takes".
## Four minutes, not ten. Ten was a whole round of the default length, so
## on any round of ten minutes or less the stalemate rule never fired at
## all and it only ever did anything on an unlimited one.
const STALE_SECONDS := 240.0

## Is it time for the guard to go out?
static func pushing(seconds_left: float, seconds_total: float) -> bool:
	if seconds_total <= 0.0:
		return false
	if seconds_left <= minf(PUSH_SECONDS, seconds_total * PUSH_FRACTION):
		return true
	return (seconds_total - seconds_left) >= STALE_SECONDS

## HOW MUCH OF A TEAM STAYS HOME WITH THE CLOCK NEARLY GONE.
##
## Defence wins this mode, which is the point of it — and it means that
## left to themselves every side digs in and nothing happens for ten
## minutes. The table pays nothing past three survivors, so a round where
## everybody successfully holds is a round where nobody scores: the most
## defensive play available is also the one that guarantees you gain
## nothing. That is a rule fighting itself.
##
## So the clock does the arguing. With most of the round gone, half the
## guard goes out and looks for a flag, because at that point holding one
## is worth nothing and taking one is worth everything. A side is never
## left completely open — somebody always stays on the pole.
static func keepers_left(team_size: int, push: bool) -> int:
	var home := keepers(team_size)
	if not push or home <= 1:
		return home
	return maxi(1, home / 2)
