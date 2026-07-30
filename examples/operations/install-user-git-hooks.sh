#!/bin/sh
# Security mutation: inspect target paths, then install Tama's user-global Git dispatchers.
# TAMA_APPLY must be set explicitly because the second command writes hook entrypoints and Git config.
set -eu

tama install-plan

: "${TAMA_APPLY:?set TAMA_APPLY only after reviewing the install plan}"
if [ "$TAMA_APPLY" != yes ]; then
  echo 'TAMA_APPLY must equal yes'
  false
fi

tama install --set-git-config

# Confirm catalog health and the resulting installation targets.
tama status
tama install-plan
