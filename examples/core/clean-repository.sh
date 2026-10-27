#!/bin/sh
# Mutation and provider-facing: let the Brama route Tama resolves repair one
# recoverable repository. Commit or back up unrelated work before running this
# command.
set -eu

: "${REPOSITORY:?set REPOSITORY to an existing Git working tree}"
MAX_ROUNDS=${MAX_ROUNDS:?set MAX_ROUNDS to the allowed repair-round limit}

tama violations clean \
  --repo "$REPOSITORY" \
  --max-rounds "$MAX_ROUNDS"

# Prove the final observable state with an independent read-only scan.
tama violations find --repo "$REPOSITORY"
