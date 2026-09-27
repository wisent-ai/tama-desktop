#!/bin/bash
# The committed Tama source a desktop release packages, pinned by commit.
#
#   Release/tama-source.sh pin --revision FULL_TAMA_COMMIT
#   Release/tama-source.sh verify
#   Release/tama-source.sh unpack --destination DIR
#
# `pin` archives one committed revision of the sibling Tama checkout with
# `git archive --prefix=tama/`, which records the commit in the archive's
# global header, stores it at Release/vendor/tama/<commit>/source.tar.gz with
# its digest beside it, and moves Release/tama-revision to it. `verify` checks
# the archive's SHA-256 and its recorded commit against the pin and prints the
# archive path. `unpack` verifies, refuses members outside tama/ and a
# committed identity marker, extracts, and writes .tama-source-archive.json,
# the marker `tama hooks source-identity` reads.
set -euo pipefail

PROJECT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$PROJECT/Release/tama-revision"
VENDOR="$PROJECT/Release/vendor/tama"
SOURCE="$(dirname -- "$PROJECT")/tama"
MARKER=".tama-source-archive.json"
# The marker schema `tama hooks source-identity` accepts (MARKER_SCHEMA in
# tama-cli's hooks/package/identity/archive.rs).
MARKER_SCHEMA="1"
COMMIT_PATTERN='^[0-9a-f]{40}$'
DIGEST_PATTERN='^[0-9a-f]{64}$'
DIGEST_ALGORITHM="256"

refuse() {
  printf 'Tama source pin refused: %s\n' "$*" >&2
  exit 1
}

digest() {
  shasum -a "$DIGEST_ALGORITHM" "$1" | cut -d ' ' -f 1
}

archive_path() {
  printf '%s/%s/source.tar.gz\n' "$VENDOR" "$1"
}

pinned_revision() {
  [ -f "$PIN" ] || refuse "$PIN is absent"
  local revision
  revision="$(tr -d '[:space:]' < "$PIN")"
  printf '%s' "$revision" | grep -Eq "$COMMIT_PATTERN" || refuse "$PIN: revision must be a full Git commit"
  printf '%s\n' "$revision"
}

pinned_digest() {
  local checksum sha
  checksum="$(dirname -- "$(archive_path "$1")")/source.sha256"
  [ -f "$checksum" ] || refuse "$checksum is absent"
  sha="$(tr -d '[:space:]' < "$checksum")"
  printf '%s' "$sha" | grep -Eq "$DIGEST_PATTERN" || refuse "$checksum: expected a full archive digest"
  printf '%s\n' "$sha"
}

verify_archive() {
  local archive="$1" revision="$2" sha="$3" actual observed
  [ -f "$archive" ] || refuse "$archive is absent"
  actual="$(digest "$archive")"
  [ "$actual" = "$sha" ] || refuse "$archive: expected sha256 $sha, observed $actual"
  observed="$(gzip -dc "$archive" | git get-tar-commit-id || true)"
  [ "$observed" = "$revision" ] || refuse "$archive: expected Git commit $revision, observed '${observed}'"
}

verify() {
  local revision sha archive
  revision="$(pinned_revision)"
  sha="$(pinned_digest "$revision")"
  archive="$(archive_path "$revision")"
  verify_archive "$archive" "$revision" "$sha"
  printf '%s\n' "$archive"
}

json_string() {
  local text="${1//\\/\\\\}"
  printf '"%s"' "${text//\"/\\\"}"
}

unpack() {
  [ "${1:-}" = "--destination" ] && [ -n "${2:-}" ] || refuse "usage: tama-source.sh unpack --destination DIR"
  local revision sha archive destination root outside
  revision="$(pinned_revision)"
  sha="$(pinned_digest "$revision")"
  archive="$(archive_path "$revision")"
  verify_archive "$archive" "$revision" "$sha"
  mkdir -p "$2"
  destination="$(CDPATH= cd -- "$2" && pwd)"
  root="$destination/tama"
  [ ! -e "$root" ] || refuse "refusing to overwrite an existing source directory: $root"
  outside="$(tar -tzf "$archive" | grep -Ev '^tama(/|$)' || true)"
  [ -z "$outside" ] || refuse "archive member is outside the Tama source: ${outside%%$'\n'*}"
  ! tar -tzf "$archive" | grep -Eq '(^|/)\.\.(/|$)' || refuse "archive member climbs out of the Tama source"
  # -p keeps the archive's modes, as `tama hooks source-identity` does when it
  # extracts the same archive to compare: an input's mode is part of it.
  tar -xpzf "$archive" -C "$destination"
  printf '{"archive": %s, "revision": %s, "schema": %s, "sha256": %s}\n' \
    "$(json_string "$archive")" "$(json_string "$revision")" "$MARKER_SCHEMA" "$(json_string "$sha")" > "$root/$MARKER"
  printf '%s\n' "$root"
}

pin() {
  [ "${1:-}" = "--revision" ] && [ -n "${2:-}" ] || refuse "usage: tama-source.sh pin --revision FULL_TAMA_COMMIT"
  local requested="$2" resolved previous="" staging archive sha destination superseded
  resolved="$(git -C "$SOURCE" rev-parse --verify --end-of-options "$requested^{commit}")" \
    || refuse "$SOURCE does not hold commit $requested"
  [ "$requested" = "$resolved" ] || refuse "supply the full committed source revision, not '$requested'; resolved $resolved"
  [ ! -f "$PIN" ] || previous="$(pinned_revision)"
  staging="$PROJECT/.build/source-pin"
  mkdir -p "$staging"
  work="$(mktemp -d "$staging/pin-XXXXXX")"
  trap 'rm -rf "$work"' EXIT
  archive="$work/source.tar.gz"
  git -C "$SOURCE" archive --format=tar.gz --prefix=tama/ --output="$archive" "$resolved"
  sha="$(digest "$archive")"
  verify_archive "$archive" "$resolved" "$sha"
  destination="$(archive_path "$resolved")"
  mkdir -p "$(dirname -- "$destination")"
  if [ -e "$destination" ]; then
    [ "$(digest "$destination")" = "$sha" ] || refuse "refusing to replace different bytes at immutable source $destination"
  else
    mv "$archive" "$destination"
  fi
  printf '%s\n' "$sha" > "$work/source.sha256"
  mv "$work/source.sha256" "$(dirname -- "$destination")/source.sha256"
  printf '%s\n' "$resolved" > "$work/tama-revision"
  mv "$work/tama-revision" "$PIN"
  if [ -n "$previous" ] && [ "$previous" != "$resolved" ]; then
    superseded="$(dirname -- "$(archive_path "$previous")")"
    rm -f "$superseded/source.tar.gz" "$superseded/source.sha256"
    rmdir "$superseded" 2>/dev/null || true
  fi
  printf '{"revision": "%s", "sha256": "%s"}\n' "$resolved" "$sha"
}

case "${1:-}" in
  pin) shift; pin "$@" ;;
  verify) verify ;;
  unpack) shift; unpack "$@" ;;
  *) refuse "usage: tama-source.sh <pin --revision COMMIT|verify|unpack --destination DIR>" ;;
esac
