#!/usr/bin/env bash
#
# Put a specific build live. Runs ON the host; CI invokes it over ssh:
#
#     echo "$GHCR_TOKEN" | ssh deploy@battlebox.games \
#       /srv/battlebox/deploy.sh <image-tag> [<image-repository>]
#
# The registry token arrives on stdin rather than in the arguments, so it
# never appears in the host's process list or in bash history.
#
# This does not "restart the site" — it pins an exact image, brings the
# stack up, and then PROVES the new build is the one answering. A deploy
# that silently left the old container running is the failure this is
# written against: `docker compose up` is a no-op when nothing changed, so
# without the version check at the bottom, a broken push and a successful
# one look identical from CI.

set -euo pipefail

TAG="${1:?usage: deploy.sh <image-tag> [<image-repository>]}"
# The repository comes from CI, which knows it as github.repository. It
# was hardcoded here, which meant renaming the GitHub repo would have left
# the host pulling an image nothing pushes to any more — and the deploy
# would have "succeeded" against the last build of the old name.
REPO="${2:-ianbelcher/battlebox.games}"
IMAGE="ghcr.io/${REPO}:${TAG}"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# The registry is private-by-default for a package pushed from a repo, so
# log in when CI gives us a credential. If stdin is empty (a hand-run
# deploy of an image already on the box) carry on without one.
if [ ! -t 0 ]; then
  TOKEN="$(cat || true)"
  if [ -n "$TOKEN" ]; then
    echo "==> logging in to ghcr.io"
    printf '%s' "$TOKEN" | docker login ghcr.io -u "${REGISTRY_USER:-$(dirname "$REPO")}" --password-stdin
  fi
fi

echo "==> pinning $IMAGE"
printf 'BATTLEBOX_IMAGE=%s\n' "$IMAGE" > .env

echo "==> pulling"
# Just the game's own images. Anything a deployment adds in front — a TLS
# terminator, say — lives in its own docker-compose.override.yml, which
# `docker compose` merges in automatically and which is not this repo's
# business.
docker compose pull --quiet lobby web

echo "==> bringing the stack up"
# NOT --remove-orphans: a deployment's own override file may add services
# this repository has never heard of, and removing them would take the
# site's TLS down on every deploy.
docker compose up -d

# ------------------------------------------------------------------
# Prove it.
# ------------------------------------------------------------------

echo "==> waiting for the web role"
ok=""
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 http://127.0.0.1:8081/healthz >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 2
done
if [ -z "$ok" ]; then
  echo "FATAL: nothing answering on 8081 after two minutes." >&2
  docker compose ps
  docker compose logs --tail 60
  exit 1
fi

# version.txt is written into the image at build time from the commit sha,
# so this compares what is SERVING against what we asked for — not what
# docker thinks it pulled.
want="$(printf '%s' "$TAG" | cut -c1-12)"
got="$(curl -fsS --max-time 5 http://127.0.0.1:8081/version.txt | tr -d '[:space:]')"
if [ "$want" != "$got" ]; then
  echo "FATAL: asked for $want, but the site is serving $got." >&2
  docker compose ps
  exit 1
fi

# A real WebSocket handshake against the path a browser player uses. 101 is
# the world accepting; 502 is nginx up with nothing behind it, which is
# exactly the half-deployed state that otherwise reads as success.
#
# This one talks plain http to a local port, so it is HTTP/1.1 already. If
# you ever repoint it at https://battlebox.games/ws by hand, add --http1.1:
# over HTTP/2 the Connection and Upgrade headers are illegal, curl drops
# them, and you get a 502 that looks like a broken proxy and is not.
echo "==> waiting for the lobby and the always-on game"
code=""
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: ZGVwbG95Y2hlY2sxMjM0NQ==' \
    http://127.0.0.1:8081/ws || true)"
  [ "$code" = "101" ] && break
  sleep 2
done
if [ "$code" != "101" ]; then
  echo "FATAL: /ws answered $code, not 101 — the world server is not up." >&2
  docker compose logs --tail 60 lobby
  exit 1
fi

# A socket that upgrades proves a room is running. It does NOT prove the
# lobby can list or start one — and a site where Play works but nobody can
# create a game is broken in a way the check above cannot see.
echo "==> checking the lobby can list games"
rooms="$(curl -fsS --max-time 5 http://127.0.0.1:8081/api/rooms || true)"
case "$rooms" in
  *'"house"'*) echo "    the always-on game is listed" ;;
  *)
    echo "FATAL: /api/rooms did not list the always-on game: $rooms" >&2
    docker compose logs --tail 60 lobby
    exit 1
    ;;
esac

# Old images pile up fast — each one carries a 60 MB browser build and four
# native clients. Keep the box from filling up silently.
docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true

echo "==> live: $IMAGE (serving $got)"
docker compose ps
