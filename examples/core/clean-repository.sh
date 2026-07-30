#!/bin/sh
# Mutation and provider-facing: let the selected model repair one recoverable repository.
# Commit or back up unrelated work before running this command.
set -eu

: "${REPOSITORY:?set REPOSITORY to an existing Git working tree}"
TAMA_MODEL=${TAMA_MODEL:-codex}
MAX_ROUNDS=${MAX_ROUNDS:?set MAX_ROUNDS to the allowed repair-round limit}

tama clean \
  --repo "$REPOSITORY" \
  --model "$TAMA_MODEL" \
  --max-rounds "$MAX_ROUNDS"

# Prove the final observable state with an independent read-only scan.
tama find-violations --repo "$REPOSITORY"
