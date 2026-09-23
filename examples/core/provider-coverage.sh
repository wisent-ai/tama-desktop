#!/bin/sh
# Read-only: registry-declared provider coverage, the same request the Coverage
# screen runs; this is not live execution evidence.
# Requires the `tama` CLI on PATH and python3.
set -eu

# One process answers and exits. It prints one response event whose `json` is
# every provider, event, runtime event, and hook ID mapping, and it exits
# non-zero when the status in that event is a refusal.
tama request coverage < /dev/null | python3 -m json.tool
