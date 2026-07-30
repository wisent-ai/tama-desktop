#!/bin/sh
# Read-only: scan one existing repository and report the first violation per file.
set -eu

: "${REPOSITORY:?set REPOSITORY to an existing Git working tree}"

tama find-violations --repo "$REPOSITORY"

# Use JSON for automation or archival evidence.
tama find-violations --repo "$REPOSITORY" --json
