#!/bin/bash
# Runs the tests for all images or the given images
# Usage: tests/run.sh <static|build|all> [--keep] [image...]
#   static  check asset lists, checksums, maplists and map changes, and shellcheck the scripts
#   build   build the images and check the server files inside them (--keep saves the maps to tests/out/<image>)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# Keep Git Bash on Windows from rewriting container paths
export MSYS_NO_PATHCONV=1

SUITE="${1:-}"
shift || true
KEEP=''
if [ "${1:-}" = '--keep' ]; then
    KEEP='--keep'
    shift
fi

if [ $# -gt 0 ]; then
    IMAGES=("$@")
else
    IMAGES=()
    for dir in images/*/; do
        IMAGES+=("$(basename "$dir")")
    done
fi

for image in "${IMAGES[@]}"; do
    if [ ! -d "images/$image" ]; then
        echo "Unknown image: $image"
        exit 2
    fi
done

# Use the first working Python 3 (python3 can be a Microsoft Store shortcut on Windows)
for candidate in python3 python; do
    if "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 6))' > /dev/null 2>&1; then
        export PYTHON="$candidate"
        break
    fi
done
if [ -z "${PYTHON:-}" ]; then
    echo 'Python 3 is required'
    exit 2
fi

FAILED=()

run_static() {
    echo '### Static checks'
    local paths=()
    for image in "${IMAGES[@]}"; do
        paths+=("images/$image")
    done
    "$PYTHON" tests/static/check.py "${paths[@]}" || FAILED+=('static checks')

    echo '### Shellcheck'
    local scripts=()
    for image in "${IMAGES[@]}"; do
        scripts+=(images/"$image"/assets/build/build.sh images/"$image"/assets/runtime/*.sh)
    done
    if docker run --rm -v "$(pwd -W 2> /dev/null || pwd):/mnt" -w /mnt koalaman/shellcheck:stable \
        --rcfile tests/.shellcheckrc --severity warning --format gcc "${scripts[@]}"; then
        echo "ok   ${#scripts[@]} scripts"
    else
        FAILED+=('shellcheck')
    fi
}

run_build() {
    for image in "${IMAGES[@]}"; do
        echo "### Build $image"
        tests/build/test-image.sh "$image" $KEEP || FAILED+=("build $image")
    done
}

case "$SUITE" in
    static) run_static ;;
    build) run_build ;;
    all) run_static; run_build ;;
    *) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

echo
if [ ${#FAILED[@]} -gt 0 ]; then
    printf 'Failed: %s\n' "${FAILED[@]}"
    exit 1
fi
echo 'All tests passed'
