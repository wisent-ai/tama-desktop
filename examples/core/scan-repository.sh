#!/bin/sh
# Read-only: scan one existing repository and report the first violation per file.
# Exit status is the scan verdict: 0 clean, 1 violations reported.
set -eu

: "${REPOSITORY:?set REPOSITORY to an existing Git working tree}"

tama violations find --repo "$REPOSITORY" || SCAN=$?

# Use JSON for automation or archival evidence.
tama violations find --repo "$REPOSITORY" --json > /dev/null || SCAN=$?

exit "${SCAN:-0}"
