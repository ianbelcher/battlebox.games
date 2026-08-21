#!/usr/bin/env sh

# Shell 'strict' mode
set -ue

# A local build, for looking at the image by hand. CI does not use this —
# it runs `docker build` itself so it can tag and push in one place (see
# .github/workflows/deploy.yml).
#
# The sha is passed whole; the Dockerfile shortens it, so a build from here
# and a build from CI stamp version.txt identically.
SHA="${GIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo dev)}"
docker build --build-arg GIT_SHA="$SHA" --tag battlebox .
