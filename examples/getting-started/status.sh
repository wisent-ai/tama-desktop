#!/bin/sh
# Read-only: summarize catalog health and registry-declared provider coverage.
# Requires the `tama` CLI on PATH.
set -eu

tama status

# Use JSON when another command will consume the result.
tama status --json

# After local provider adapters are configured, include install-drift checks:
# tama status --runtime
