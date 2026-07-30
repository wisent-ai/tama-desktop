#!/bin/sh
# Read-only: list the hook catalog, then inspect one exact hook.
set -eu

HOOK_ID=${HOOK_ID:-block-hook-config-edits-without-consent}

tama hooks list
tama hooks show "$HOOK_ID"

# Machine-readable equivalents.
tama hooks list --json
tama hooks show "$HOOK_ID" --json
