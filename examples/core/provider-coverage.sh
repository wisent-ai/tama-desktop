#!/bin/sh
# Read-only: show every provider, then inspect registry-declared mappings; this is not live execution evidence.
set -eu

TAMA_PROVIDER=${TAMA_PROVIDER:-codex}

tama provider list
tama provider coverage "$TAMA_PROVIDER"

# JSON retains every provider, event, runtime event, and hook ID mapping.
tama provider coverage "$TAMA_PROVIDER" --json
