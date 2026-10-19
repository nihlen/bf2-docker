#!/bin/bash
# Prints a JSON array of the images to build, e.g. ["netsky-2v2","netsky-inf"]
# Usage: .github/scripts/changed-images.sh <base commit|all> [head commit]
#   An image is selected if a file in images/<image>/ changed since the base commit.
#   All images are selected if shared files changed, or the base is "all", empty or unknown (e.g. a new branch).
set -euo pipefail
cd "$(dirname "$0")/../.."

BASE="${1:-all}"
HEAD="${2:-HEAD}"

# Changes to these affect every image
SHARED='^(tests/|\.github/|\.gitattributes$)'

all_images() {
    for dir in images/*/; do
        basename "$dir"
    done
}

to_json() {
    local json='' image
    while read -r image; do
        [ -n "$image" ] && json="$json${json:+,}\"$image\""
    done
    echo "[$json]"
}

if [ "$BASE" = 'all' ] || [ -z "${BASE//0/}" ] || ! git cat-file -e "$BASE^{commit}" 2> /dev/null; then
    all_images | to_json
    exit 0
fi

changed=$(git diff --name-only "$BASE" "$HEAD")
if grep -qE "$SHARED" <<< "$changed"; then
    all_images | to_json
    exit 0
fi

# Only images that still exist, deleted images can't be built
{ grep -oE '^images/[^/]+/' <<< "$changed" || true; } | cut -d/ -f2 | sort -u | while read -r image; do
    if [ -f "images/$image/Dockerfile" ]; then
        echo "$image"
    fi
done | to_json
