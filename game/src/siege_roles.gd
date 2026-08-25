class_name SiegeRoles
## WHO DEFENDS, WHO ATTACKS, AND WHICH FLAG THEY GO FOR.
##
## This was four functions in bot_director threaded through two other
## modules, and every one of them needed a live world to answer. So the
## one question that decides whether a round of last flag standing is a
## game — does a real attack ever leave the base? — could not be asked
## anywhere except by playing one and watching.
##
## It went wrong exactly there. Two thirds of every team stayed home,
## which is what had been asked for, and two attackers against three
## defenders behind a wall take nothing: seventeen of twenty-six players
## sat within fourteen blocks of their own flag, four were out in the
## field, and no flag fell in the whole measured round. From the outside
## that is "all of the bots just huddle around the flag and don't do
## anything", and it is not a bug in any one line — it is a ratio, which
## is the kind of thing a pure module can be asked about directly.
##
## Nothing here knows about the world. It takes numbers and gives back
## numbers, so the invariants below are testable: SOMEBODY always goes
## out, somebody always stays, and every standing enemy flag gets
## somebody sent at it.

enum { DEFEND, ATTACK }

## How many of a team mind its own flag.
##
## Capture the flag posts a token guard — at most two, however big the
## team — because losing a flag there costs a point and nothing else.
## Last flag standing is a siege and posts about half, which is far more
## defensive without being everybody. See HoldoutRules.keepers.
static func keepers(team_size: int, siege: bool, pushing := false) -> int:
	if not siege:
		return clampi(team_size / 3, 0, 2)
	return HoldoutRules.keepers_left(team_size, pushing)

## What this seat is doing. Seats below the keeper count mind the shop.
##
## By SEAT rather than by anything about the player, so a bot keeps the
## same job all round instead of the whole side changing its mind at once
## whenever somebody goes down.
static func job(seat: int, keeper_count: int) -> int:
	return DEFEND if seat >= 0 and seat < keeper_count else ATTACK

## Which attacker this is, counting past the ones minding the shop.
static func raider_index(seat: int, keeper_count: int) -> int:
	return maxi(seat - keeper_count, 0)

## Which team's flag this seat goes for, dealt round-robin across the
## flags actually standing so a side of four with three enemies puts
## somebody on each. -1 when there is nothing left to run at.
static func target(seat: int, keeper_count: int, standing: Array) -> int:
	if standing.is_empty():
		return -1
	return int(standing[raider_index(seat, keeper_count) % standing.size()])

## THE INVARIANT THAT MATTERS: does this team actually send anybody?
## A side that keeps everyone home cannot win a mode that is decided by
## taking flags, and five such sides is a round where nothing happens.
static func attackers(team_size: int, siege: bool, pushing := false) -> int:
	return maxi(0, team_size - keepers(team_size, siege, pushing))
