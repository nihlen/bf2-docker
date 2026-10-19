#!/bin/bash
# Builds an image and checks the server files inside it
# Usage: tests/build/test-image.sh <image> [--keep]
set -euo pipefail

IMAGE="$1"
KEEP="${2:-}"
TAG="bf2-docker-test/$IMAGE"
OUT="tests/out/$IMAGE"
SRV='/home/bf2/tmp/srv'

docker build -t "$TAG" "images/$IMAGE"

rm -rf "$OUT"
mkdir -p "$OUT"
container=$(docker create "$TAG")
trap 'docker rm "$container" > /dev/null' EXIT
docker cp -q "$container:$SRV/mods/bf2/levels" "$OUT/levels"
docker cp -q "$container:$SRV/mods/bf2/settings/maplist.con" "$OUT/maplist.con"

status=0
"$PYTHON" tests/build/check_levels.py "images/$IMAGE" "$OUT" || status=$?

if [ "$KEEP" != "--keep" ]; then
    rm -rf "$OUT"
fi
exit $status
