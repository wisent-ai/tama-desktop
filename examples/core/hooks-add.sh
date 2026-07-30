#!/bin/sh
# Maintainer mutation: register one catalogued hook in one explicit writable policy source tree.
# Required variables prevent accidental mutation of a signed app bundle or installed release.
set -eu

: "${TAMA_POLICY_ROOT:?set TAMA_POLICY_ROOT to the writable Tama policy source tree}"
: "${HOOK_ID:?set HOOK_ID to an ID present in catalog-metadata.json}"
: "${HOOK_EVENT:?set HOOK_EVENT to an existing registry event}"
: "${HOOK_COMMAND:?set HOOK_COMMAND to the exact executable command}"

tama hooks add "$HOOK_ID" \
  --event "$HOOK_EVENT" \
  --command "$HOOK_COMMAND" \
  --root "$TAMA_POLICY_ROOT"

# Inspect the resealed result.
tama hooks show "$HOOK_ID" --root "$TAMA_POLICY_ROOT"
tama hooks validate --root "$TAMA_POLICY_ROOT"

# Deliberate rollback command:
# tama hooks remove "$HOOK_ID" --event "$HOOK_EVENT" --root "$TAMA_POLICY_ROOT"
