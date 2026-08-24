#!/bin/sh
# Read-only: live supervised sessions, every installed release verified against
# its content-addressed directory name, and the second integrity gate an
# emergency enable would meet.
# Executed end-to-end with pasted output in docs/walkthrough-runtime-status.md.
set -eu

cd "$(dirname "$0")/../.."

TAMA_CLI=${TAMA_CLI:-.build/Tama.app/Contents/Resources/hooks-release/bin/tama-cli}

# One line per live session: agent id, session id, hook state.
# Prints nothing (exit 0) when no supervised session is running.
"$TAMA_CLI" sessions
"$TAMA_CLI" sessions --json

# Digest every tree under hooks-runtime/releases against its directory name.
# TAMA_HOME selects another home; TAMA_HOOK_RELEASE_ROOT another bundled release.
python3 Scripts/verify_installed_releases.py
