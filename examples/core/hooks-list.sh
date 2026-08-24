#!/bin/sh
# Read-only: list the hook catalog, then inspect one exact hook.
set -eu

HOOK_ID=${HOOK_ID:-block-hook-config-edits-without-consent}

tama list
tama show "$HOOK_ID"

# Machine-readable equivalents.
tama list --json
tama show "$HOOK_ID" --json
