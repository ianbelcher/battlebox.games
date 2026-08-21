#!/usr/bin/env bash
#
# Prove the browser build actually works, in a real browser.
#
#   tools/webtest.sh
#
# Exports the Web preset, serves it with the PRODUCTION nginx.conf (paths
# rewritten, nothing else) behind a local TLS terminator, starts a headless
# world server, and drives the whole thing in headless Chrome.
#
# It asserts the three things that are each individually fatal and each
# individually invisible:
#   - the page is cross-origin isolated  (no isolation -> no threads)
#   - SharedArrayBuffer exists           (no SAB -> Godot dies on startup)
#   - the game reaches the world server over wss
# and then joins a player, because loading is not playing.
#
# The TLS terminator is not an approximation of production, it IS the
# production shape: a TLS terminator holds the certificate and
# proxies to this same plain-http nginx. So this test also proves that the
# Cross-Origin-* headers and the /ws upgrade survive a hop through a proxy,
# which is the arrangement that actually ships.
#
# Needs: godot 4.7.1 with web export templates, nginx, node, Google Chrome.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
GAME="$ROOT/game"
WORK="${WORLD_WEBTEST_DIR:-/tmp/battlebox-webtest}"
PORT_HTTPS=8443
PORT_HTTP=8081
PORT_GAME=9081

echo "==> exporting the Web build"
mkdir -p "$GAME/build/play"
godot --headless --path "$GAME" --export-release "Web" "$GAME/build/play/index.html" \
  2>&1 | tail -2

echo "==> staging into $WORK"
rm -rf "$WORK"
mkdir -p "$WORK"/{tls,www,logs}
# Same layout production uses: the GAME at the root, the entry page at
# /install. Copy order matters — the entry page landing on top of the
# game's own index.html is exactly the mistake this test exists to catch.
cp -r "$GAME/build/play/." "$WORK/www/"
cp "$ROOT/web/index.html" "$WORK/www/install.html"
cp "$ROOT/web/voice.js" "$WORK/www/voice.js"
cp "$ROOT/web/boot.css" "$ROOT/web/boot.js" "$WORK/www/"
[ -f "$ROOT/web/demo.mp4" ] && cp "$ROOT/web/demo.mp4" "$WORK/www/demo.mp4"
grep -q 'Godot\|engine.startGame' "$WORK/www/index.html" \
  || { echo "the web root is not the game"; exit 1; }

# A throwaway certificate for the test, standing in for the Let's Encrypt
# one a terminator holds in production. It only has to make the browser treat the
# page as a secure context.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/tls/test.key" -out "$WORK/tls/test.crt" \
  -subj "/CN=BattleBox test" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1

# The real nginx.conf with only the paths moved — testing a hand-written
# copy of the config would prove nothing about the one we ship — plus a
# terminator server block in front of it, which is the terminator's job in
# production. Everything the game depends on (the Cross-Origin-* headers,
# the wasm content type, the /ws upgrade) comes from the shipped config and
# is merely relayed by the terminator, exactly as it is on the real box.
MIME="$(nginx -V 2>&1 | tr ' ' '\n' | grep -- '--conf-path=' | cut -d= -f2)"
MIME="$(dirname "${MIME:-/etc/nginx/nginx.conf}")/mime.types"
python3 - "$ROOT/nginx.conf" "$WORK" "$MIME" "$PORT_HTTPS" "$PORT_HTTP" <<'PY'
import sys
src, work, mime, https_port, http_port = sys.argv[1:6]
s = open(src).read()
s = s.replace('user www-data;\n', '')
s = s.replace('pid /run/nginx.pid;', f'pid {work}/nginx.pid;')
s = s.replace('include /etc/nginx/mime.types;', f'include {mime};')
s = s.replace('/opt/battlebox/web', f'{work}/www')
s = s.replace('access_log /dev/stdout;', f'access_log {work}/logs/access.log;')
s = s.replace('error_log  /dev/stderr warn;', f'error_log {work}/logs/error.log warn;')

terminator = f"""
    # Stand-in for the terminator: terminate TLS and relay everything, headers and
    # websocket upgrades included, to the shipped config above.
    server {{
        listen {https_port} ssl;
        ssl_certificate     {work}/tls/test.crt;
        ssl_certificate_key {work}/tls/test.key;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {{
            proxy_pass http://127.0.0.1:{http_port};
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_buffering off;
        }}
    }}
}}
"""
# "Connection: upgrade" must only be sent for requests that ARE upgrades;
# sending it on every request breaks keep-alive for the 60 MB of static
# files. This is the map a real terminator applies automatically.
s = s.replace('http {', 'http {\n    map $http_upgrade $connection_upgrade '
              '{ default upgrade; "" close; }\n', 1)
s = s.rstrip()
assert s.endswith('}'), "nginx.conf should end with the closing http brace"
s = s[:-1] + terminator
open(f'{work}/nginx.conf', 'w').write(s)
PY

cleanup() {
  nginx -s quit -c "$WORK/nginx.conf" -p "$WORK" 2>/dev/null || true
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> starting nginx and a world server"
nginx -t -c "$WORK/nginx.conf" -p "$WORK" 2>&1 | tail -1
nginx -c "$WORK/nginx.conf" -p "$WORK"
WORLD_PORT="$PORT_GAME" \
  godot --headless --path "$GAME" > "$WORK/logs/server.log" 2>&1 &
SERVER_PID=$!
sleep 8
grep -i listening "$WORK/logs/server.log" || { echo "server never listened"; exit 1; }

echo "==> driving it in Chrome"
cd "$WORK"
npm init -y >/dev/null 2>&1
npm install puppeteer-core >/dev/null 2>&1
cp "$HERE/webtest_play.js" "$WORK/play.js"
node play.js "https://localhost:$PORT_HTTPS/" 90 "$WORK/shot.png"
