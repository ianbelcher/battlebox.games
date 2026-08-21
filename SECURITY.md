# Reporting a security problem

Use GitHub's private vulnerability reporting: **Security → Report a
vulnerability** on this repository. Please do not open a public issue for
anything that could be used against players before it is fixed.

## What this project is, in security terms

BattleBox is a children's game with no accounts, no passwords, no payment
and no personal data. Nothing about a player is stored anywhere: a world
lives in a server process's memory and dies with it, and names and
character choices are kept by each player's own browser.

Room codes are not a security boundary and are not meant to be. A private
game is private because nobody has a reason to look for it, not because
`brave-otter` is hard to guess. Do not put anything in a room name you
would not want a stranger to read.

## What is worth reporting

- Anything that lets one player affect another player's machine
- Anything that lets a client crash, hang or exhaust a server, or start
  rooms without limit
- Anything that escapes the browser sandbox or the server container
- Cross-site scripting, including through a room name

## What is not

- That room codes are guessable. They are; see above.
- That a server trusts a client's own player position. It does, by design:
  machines are authoritative over their own players' movement. There is
  nothing to win.
- Griefing inside a game. Anyone can dig anyone's fort. That is the game.

## If you run your own

Two things are worth knowing before you put this on the internet.

**Do not build it on a self-hosted CI runner from a public repository.** A
pull request from a fork supplies its own workflow file, so it can add
steps that run on that machine, and approving the PR to look at it is
enough. This repository builds on hosted runners for exactly that reason.

**A room is a process.** `LOBBY_MAX_ROOMS` is the only thing standing
between the create endpoint and every core on the box; the default of 8 is
chosen for a 4 GB host. There is no other rate limiting.
