#!/usr/bin/env bash
# Format all source files under dsl/, kernel/, lib/, test/ via
# /scripts/autostyle.
# Usage: tools/format-all.sh [path ...]
# With no arguments, formats the four source directories.
set -euo pipefail

AUTOSTYLE="${AUTOSTYLE:-/scripts/autostyle}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
DIRS=(dsl kernel lib test)

cd "$REPO_ROOT"

if [ $# -gt 0 ]; then
    targets=("$@")
else
    targets=("${DIRS[@]}")
fi

for target in "${targets[@]}"; do
    if [ ! -e "$target" ]; then
        echo "skip: $target does not exist" >&2
        continue
    fi
    "$AUTOSTYLE" "$target"
done
