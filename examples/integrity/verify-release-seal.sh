#!/bin/sh
# Read-only: prove a sealed hook release still digests to its recorded releaseId,
# and when it does not, name the files written after the seal.
# Executed end-to-end with pasted output at https://tama.wisent.com/docs/walkthrough-verify-release/.
set -eu

cd "$(dirname "$0")/../.."

# Default: the release inside the built app; pass any release root as $1.
RELEASE_ROOT=${1:-.build/Tama.app/Contents/Resources/hooks-release}

python3 Scripts/verify_hook_release.py "$RELEASE_ROOT"

# The same question answered with the installer's own digest implementation,
# plus build-residue attribution on mismatch.
python3 Scripts/report_hook_release_integrity.py "$RELEASE_ROOT"
