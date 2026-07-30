#!/bin/sh
# Maintainer mutation: remove one hook occurrence from an explicit writable policy source tree.
# Inspect and record the existing command first so the occurrence can be restored exactly.
set -eu

: "${TAMA_POLICY_ROOT:?set TAMA_POLICY_ROOT to the writable Tama policy source tree}"
: "${HOOK_ID:?set HOOK_ID to the catalogued hook ID}"
: "${HOOK_EVENT:?set HOOK_EVENT to the registered event}"

tama hooks show "$HOOK_ID" --root "$TAMA_POLICY_ROOT"
tama hooks remove "$HOOK_ID" \
  --event "$HOOK_EVENT" \
  --root "$TAMA_POLICY_ROOT"
tama hooks validate --root "$TAMA_POLICY_ROOT"

# Exact rollback after supplying the recorded command:
# tama hooks add "$HOOK_ID" --event "$HOOK_EVENT" --command "$HOOK_COMMAND" --root "$TAMA_POLICY_ROOT"
