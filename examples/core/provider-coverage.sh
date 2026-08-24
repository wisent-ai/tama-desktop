#!/bin/sh
# Read-only: registry-declared provider coverage from the loopback backend;
# this is not live execution evidence.
# Requires the `tama` CLI on PATH, curl, and python3.
set -eu

OUT=$(mktemp)
tama serve --port 0 > "$OUT" 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true; rm -f "$OUT"' EXIT

# The backend prints exactly one ready line: {"port":N,"ready":true}
until [ -s "$OUT" ]; do sleep 0.1; done
PORT=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['port'])" "$OUT")

# Every provider, event, runtime event, and hook ID mapping.
curl -s "http://127.0.0.1:$PORT/v1/coverage" | python3 -m json.tool
