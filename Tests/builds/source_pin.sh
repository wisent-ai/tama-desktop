#!/bin/bash
# The real source producer against the real identity reader.
#
#   bash Tests/builds/source_pin.sh [TAMA_CLI]
#
# Release/tama-source.sh unpacks the pinned Tama archive; `tama hooks
# source-identity` (default: the sibling checkout's release build) must accept
# that tree with the pinned revision and refuse it once an input is changed,
# added, removed or attributed to another commit; a second unpack must refuse
# to overwrite. Evidence — commands, exit statuses, output, failures and the
# verdict — stays under .build/source-proof/<run>; only the extracted tree is
# removed.
set -uo pipefail

PROJECT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PRODUCER="$PROJECT/Release/tama-source.sh"
CONSUMER="${1:-$(dirname -- "$PROJECT")/tama/rust/target/release/tama}"
EVIDENCE="$PROJECT/.build/source-proof/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$EVIDENCE/inputs"
LOG="$EVIDENCE/commands.log"
FAILED="$EVIDENCE/failures.txt"
: > "$FAILED"

run() {
  local out status
  out="$("$@" </dev/null 2>&1)"
  status=$?
  printf '$ %s\nexit %s\n%s\n\n' "$*" "$status" "$out" >> "$LOG"
  LAST_OUTPUT="$out"
  return "$status"
}

expect() {
  local label="$1"; shift
  if "$@"; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label"
    printf '%s\n' "$label" >> "$FAILED"
  fi
}

identity() { run "$CONSUMER" hooks source-identity --source-root "$ROOT"; }
refused() { ! "$@"; }

{
  printf 'desktop revision %s\n' "$(git -C "$PROJECT" rev-parse HEAD)"
  printf 'producer %s\n' "$(shasum -a 256 "$PRODUCER")"
  printf 'consumer %s\n' "$(shasum -a 256 "$CONSUMER")"
} > "$EVIDENCE/source.txt"
printf 'Source archive evidence: %s\n' "$EVIDENCE"

PINNED="$(tr -d '[:space:]' < "$PROJECT/Release/tama-revision")"
expect "the pinned archive verifies" run bash "$PRODUCER" verify
expect "the pinned archive unpacks" run bash "$PRODUCER" unpack --destination "$EVIDENCE/inputs"
ROOT="$EVIDENCE/inputs/tama"
trap 'rm -rf "$EVIDENCE/inputs"' EXIT

expect "the unpacked tree is accepted" identity
ACCEPTED="$LAST_OUTPUT"
expect "its identity is the pinned revision" test "$(printf '%s' "$ACCEPTED" | plutil -extract revision raw -o - -)" = "$PINNED"
expect "its identity is clean" test "$(printf '%s' "$ACCEPTED" | plutil -extract dirty raw -o - -)" = "false"
expect "the tree carries no .git" test ! -e "$ROOT/.git"

PACKAGE="$ROOT/package.json"
cp -p "$PACKAGE" "$EVIDENCE/package.json.original"
expect "a second unpack is refused" refused run bash "$PRODUCER" unpack --destination "$EVIDENCE/inputs"
expect "the refused unpack wrote nothing" cmp -s "$PACKAGE" "$EVIDENCE/package.json.original"

printf '\n' >> "$PACKAGE"
expect "a changed input is refused" refused identity
cp -p "$EVIDENCE/package.json.original" "$PACKAGE"

printf 'pub const UNCOMMITTED: bool = true;\n' > "$ROOT/rust/approval-proof-extra.rs"
expect "an added input is refused" refused identity
rm "$ROOT/rust/approval-proof-extra.rs"

rm "$PACKAGE"
expect "a missing input is refused" refused identity
cp -p "$EVIDENCE/package.json.original" "$PACKAGE"

MARKER="$ROOT/.tama-source-archive.json"
cp "$MARKER" "$EVIDENCE/marker.original"
sed -E 's/"revision": "[0-9a-f]{40}"/"revision": "0000000000000000000000000000000000000000"/' "$EVIDENCE/marker.original" > "$MARKER"
expect "a marker naming another commit is refused" refused identity
cp "$EVIDENCE/marker.original" "$MARKER"

expect "the restored tree is accepted again" identity
expect "with the identity it first had" test "$LAST_OUTPUT" = "$ACCEPTED"

if [ -s "$FAILED" ]; then
  printf '{"passed": false}\n' > "$EVIDENCE/result.json"
  printf 'failed: %s\n' "$FAILED"
  exit 1
fi
printf '{"passed": true}\n' > "$EVIDENCE/result.json"
printf 'passed\n'
