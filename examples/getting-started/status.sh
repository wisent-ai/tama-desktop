#!/bin/sh
# Read-only: every live supervised session, then catalog validation counts.
# Requires the `tama` CLI on PATH (see install-cli.sh).
set -eu

# One line per live session: agent id, session id, hook state.
tama sessions

# Use JSON when another command will consume the result.
tama sessions --json

# Supply --home <path> to read another explicit home's session records:
# tama sessions --home /Users/example

# Validation prints hook and orphan-source counts, per-hook warnings, and
# local install drift; its verdict is this script's exit status.
# `tama validate --json` is the machine-readable equivalent.
tama validate
