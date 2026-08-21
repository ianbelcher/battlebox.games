#!/usr/bin/env sh

# Shell 'strict' mode
set -ue

# One image, three roles.
#
#   lobby   the room registry: starts a world per game, proxies /ws to it
#   server  ONE world, run directly. The lobby starts these itself, so
#           this role is for a LAN box or a dev machine that wants a
#           single fixed world and no lobby at all
#   web     nginx serving the entry page, the native downloads and the
#           browser build, and proxying /ws and /api through to the lobby
#
# TLS is deliberately NOT here — put a terminator in front of this. It
# used to mint its own self-signed certificate, which meant every player
# clicked through a browser warning before they could play; a real
# certificate is both safer and one less thing for a child to get past.

ROLE="${1:-server}"

case "$ROLE" in
  lobby)
    exec python3 /opt/battlebox/lobby/lobby.py \
      --port "${LOBBY_PORT:-9080}" \
      --server "/opt/battlebox/server/battlebox-server.x86_64 --headless"
    ;;
  server)
    exec /opt/battlebox/server/battlebox-server.x86_64 --headless
    ;;
  web)
    exec nginx -g "daemon off;"
    ;;
  *)
    echo "Unknown role '$ROLE' (expected 'lobby', 'server' or 'web')" >&2
    exit 1
    ;;
esac
