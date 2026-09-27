#!/bin/sh
# Read-only: prove a sealed hook release still digests to its recorded releaseId,
# and when it does not, name the files written after the seal.
# Executed end-to-end with pasted output at https://tama.wisent.com/docs/walkthrough-verify-release/.
set -eu

cd "$(dirname "$0")/../.."

# Default: the release inside the built app; pass any release root as $1.
RELEASE_ROOT=${1:-.build/Tama.app/Contents/Resources/hooks-release}

# The installer's own digest, the recorded one, and every file written after
# the seal. Exit 1 when the release drifted.
"$RELEASE_ROOT/bin/tama" hooks integrity --release "$RELEASE_ROOT"
