#!/bin/sh
# Read-only: list the hook catalog, then inspect one exact hook.
# Usage: HOOK_ID=<an id tama list prints> sh hooks-list.sh
set -eu

HOOK_ID=${HOOK_ID:?set HOOK_ID to the id of the hook to inspect, one that tama list prints}

tama list
tama show "$HOOK_ID"

# Machine-readable equivalents.
tama list --json
tama show "$HOOK_ID" --json
