# Build stage: export the Godot project twice from the same source — the
# headless Linux server a room runs as, and the browser build players get.
#
# The browser build renders with gl_compatibility (WebGL2); project.godot
# sets that per-platform, so it is the same source with no separate
# configuration.
FROM ubuntu:24.04 AS build

ARG GODOT_VERSION=4.7.1
ARG GIT_SHA=dev

RUN apt-get update \
    && apt-get install -y --no-install-recommends wget unzip ca-certificates \
       libfontconfig1 python3 \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && unzip -q "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && rm "Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"

RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
    && mkdir -p "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
    && unzip -q "Godot_v${GODOT_VERSION}-stable_export_templates.tpz" -d /tmp/templates \
    && mv /tmp/templates/templates/* "/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable/" \
    && rm -rf /tmp/templates "Godot_v${GODOT_VERSION}-stable_export_templates.tpz"

COPY game /game
COPY lobby /lobby
COPY tools /tools
# Truncated HERE rather than by the caller, so every build agrees on the
# format no matter who started it. deploy.sh and the workflow both compare
# what the site serves against this, and a full sha from one caller and a
# short one from another would read as "the deploy did not take".
RUN printf '%s\n' "$GIT_SHA" | cut -c1-12 > /game/version.txt

# First import populates the .godot cache; it can exit non-zero on a cold
# cache even when it succeeds, hence the guard.
RUN godot --headless --path /game --import || true

# Boot the project and refuse to build if any script failed to compile.
#
# This is not belt-and-braces, it is the only thing that catches it.
# `--export-release` succeeds with a GDScript parse error in the project:
# it packs the broken script and exits 0. The result installs, serves,
# passes a version check and answers a websocket — and then the game boots
# with a dead autoload and does nothing. A deploy of that looks green at
# every single step.
#
# Booting is what surfaces it, because that is when scripts are compiled.
# --quit-after gives it a fixed number of frames so it cannot hang here.
RUN godot --headless --path /game --quit-after 240 > /tmp/boot.log 2>&1 || true; \
    if grep -qiE "SCRIPT ERROR|Parse Error|Compile Error|Failed to load script" /tmp/boot.log; then \
      echo "=== FATAL: the project does not compile ==="; \
      grep -iE -A2 "SCRIPT ERROR|Parse Error|Compile Error|Failed to load script" /tmp/boot.log; \
      exit 1; \
    fi; \
    echo "project compiles clean"

# Every symbol the UI draws has a bundled font that can draw it.
#
# Tofu is invisible to every other check here and to the browser test: a
# box with a code point in it is a SUCCESSFUL draw. Nothing errors, nothing
# logs, the screenshot looks fine unless a person reads it. On a desktop it
# cannot even be reproduced, because Godot quietly borrows missing glyphs
# from the operating system — the hearts only read "2665" in a browser,
# which has nothing to borrow from.
#
# tests/ui_glyphs.gd works out what to check by reading src/ rather than
# from a list, so adding a new emoji to a menu fails the build on the day
# it is added instead of shipping a box to the kids.
RUN godot --headless --path /game --script res://tests/ui_glyphs.gd

# The flag beacons are invisible in the same way: lose `unbreakable` and
# the flag can be dug away, lose the glow and it stops being findable
# after dark, renumber the ids and every team's pole comes out the wrong
# colour — and none of that errors, logs or shows up in a screenshot.
RUN godot --headless --path /game --script res://tests/flag_beacons.gd

# The unit suite. Fast, and the only check here that fails on logic rather
# than on something failing to load.
RUN godot --headless --path /game --script res://tests/run_tests.gd

# The lobby decides who can join what. Its tests are stdlib unittest and
# take under a second, so there is no reason for them not to gate a build.
RUN python3 -m unittest discover -s /lobby -p 'test_*.py' -v

# The Minecraft importer, against a generated region file. No maps ship,
# so nothing else exercises it — and an importer that quietly stops working
# is only discovered by somebody trying to add a map.
RUN python3 /tools/make_mca.py /tmp/mca-fixture \
    && WORLD_MCA_DIR=/tmp/mca-fixture godot --headless --path /game \
       -s res://tests/test_mca.gd

# A real client against a real server, in creative and in a battle.
#
# Everything above proves the project COMPILES. None of it proves the game
# works: an RPC sent to a node path that no longer exists does not raise in
# Godot — the call lands nowhere, the world stays empty, and every check up
# to here still passes. These two assert on the state both ends reached.
RUN cd / && python3 /tools/integration_test.py --seconds 14 \
    && python3 /tools/integration_test.py --seconds 20 --mode battle

# And the lobby, with real rooms: create a public and a private game, join
# one through the proxy, and wait for the empty ones to close themselves.
# A room that fails to reap is invisible from outside — the list looks
# right while the box fills up with abandoned worlds.
RUN cd / && python3 /tools/lobby_test.py

# Two exports: the headless server a room runs as, and the browser build
# players get. There are no native clients — the game is the web build.
RUN mkdir -p /game/build/server /game/build/play \
    && godot --headless --path /game --export-release "Linux Server" build/server/battlebox-server.x86_64 \
    && godot --headless --path /game --export-release "Web" build/play/index.html \
    && cp /game/version.txt /game/build/play/version.txt

# Runtime stage: one image, three roles. A deployment runs two containers
# from it — `lobby` (which starts a world per game) and `web` (nginx serving
# the browser build). They share a network namespace, so nginx proxies /ws
# and /api to the lobby on loopback, and the lobby proxies each socket on
# to that game's own port.
#
# The third role, `server`, is ONE world with no lobby in front of it —
# what a LAN box or a dev machine wants.
#
# No TLS in here; put a terminator in front of it. See deploy/.
FROM ubuntu:24.04

# python3 for the lobby, which is stdlib-only on purpose: no pip, no venv,
# no wheels to pin, nothing to go stale between deploys.
#
# `python3`, NOT `python3-minimal`. The minimal package is the interpreter
# WITHOUT the standard library: no asyncio, no json, no urllib, no
# dataclasses — which is to say, none of what the lobby is built out of.
# It installs cleanly and `python3 --version` answers, so the image builds
# and only falls over when the lobby is started.
RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx ca-certificates \
       libfontconfig1 curl python3 \
    && rm -rf /var/lib/apt/lists/*

# The browser build is served as application/wasm or it will not start.
# Assert it rather than trust it: a silently-wrong content type would look
# like a game bug, not a packaging one.
RUN grep -q "application/wasm" /etc/nginx/mime.types

COPY nginx.conf /etc/nginx/nginx.conf

# Check the config against THIS nginx, at build time.
#
# A config that is valid on a newer nginx and invalid here does not fail
# quietly: nginx refuses to start and the web container crash-loops, so the
# site is down while the image looks fine. That happened once with
# "http2 on;", which is 1.25.1+ while this image is on 1.24. Catching it
# here means a bad config fails the build instead of the deployment.
RUN nginx -t

COPY --from=build /game/build/server /opt/battlebox/server
COPY lobby /opt/battlebox/lobby
# The lobby imports these. Assert them HERE, in the runtime image, because
# a missing stdlib module is not a build failure — it is a site that comes
# up with no games in it.
RUN python3 -c "import asyncio, json, socket, subprocess, dataclasses, urllib.request" \
    && python3 -c "import sys; sys.path.insert(0, '/opt/battlebox/lobby'); import lobby, names; \
print('lobby imports clean, %d room codes' % names.all_codes())"
COPY maps /opt/battlebox/maps
# The browser build lands at the WEB ROOT: the game IS what the site
# serves, with nothing in front of it to click through.
COPY --from=build /game/build/play /opt/battlebox/web
# Voice chat's browser half. It has to be SAME ORIGIN: /play/ is served
# with Cross-Origin-Embedder-Policy: require-corp so Godot's threads can
# have SharedArrayBuffer, and that blocks any script fetched from a CDN.
#
# Godot generates index.html, so the tag is injected rather than authored;
# the grep afterwards is there because a silently-missing script would look
# like "voice is broken" rather than "voice was never loaded".
# The whole web directory, so the loading screen's css/js and an optional
# demo.mp4 come along without a line each. `demo.mp4` is NOT in the repo:
# drop one in web/ and it becomes the loading screen; leave it out and
# boot.js falls back to the wordmark. Either way this copy succeeds, which
# is the point of copying the directory rather than the file.
COPY web/ /opt/battlebox/websrc/
RUN cp /opt/battlebox/websrc/boot.css /opt/battlebox/websrc/boot.js \
        /opt/battlebox/web/ \
    && if [ -f /opt/battlebox/websrc/demo.mp4 ]; then \
         cp /opt/battlebox/websrc/demo.mp4 /opt/battlebox/web/demo.mp4; \
         echo "loading screen: demo.mp4 included"; \
       else \
         echo "loading screen: no demo.mp4, using the wordmark"; \
       fi
COPY web/voice.js /opt/battlebox/web/voice.js
RUN sed -i 's#</head>#<script src="voice.js"></script>\n</head>#' \
        /opt/battlebox/web/index.html \
    && grep -q 'src="voice.js"' /opt/battlebox/web/index.html
# The page being served must be the GAME. Nothing else in this pipeline
# would notice if it were not — a landing page serves, answers a version
# check and looks like a deploy that worked.
RUN grep -q 'engine.startGame\|Godot' /opt/battlebox/web/index.html
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/battlebox/server/battlebox-server.x86_64

EXPOSE 9081 8081
ENTRYPOINT ["/entrypoint.sh"]
CMD ["server"]
