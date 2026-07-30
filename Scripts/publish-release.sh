#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TAG=$(git -C "$DESKTOP_ROOT" describe --exact-match --tags HEAD || true)
case "$TAG" in
    v*) PRODUCT_VERSION=${TAG#v} ;;
    *) printf '%s\n' "Publication requires the exact release tag at HEAD."; exit ;;
esac
if [ -n "$(git -C "$DESKTOP_ROOT" status --porcelain --untracked-files=normal)" ]; then
    printf '%s\n' "Publication checkout must be clean."
    exit
fi
git -C "$DESKTOP_ROOT" verify-tag "$TAG"
RELEASE_DIR="$DESKTOP_ROOT/.build/releases/$PRODUCT_VERSION"
ARTIFACT=
for candidate in "$RELEASE_DIR"/*.zip; do
    [ -f "$candidate" ] || continue
    if [ -n "$ARTIFACT" ]; then
        printf '%s\n' "Release directory contains more than one zip artifact."
        exit
    fi
    ARTIFACT=$candidate
done
if [ -z "$ARTIFACT" ]; then
    printf '%s\n' "No packaged artifact exists for $TAG."
    exit
fi
DIGEST_FILE="$ARTIFACT.digest"
PROVENANCE_FILE="$ARTIFACT.provenance.json"
for required in "$DIGEST_FILE" "$PROVENANCE_FILE"; do
    if [ ! -f "$required" ]; then
        printf 'Missing release sidecar: %s\n' "$required"
        exit
    fi
done
read -r EXPECTED_DIGEST EXPECTED_NAME < "$DIGEST_FILE"
ACTUAL_DIGEST=$(python3 "$SCRIPT_DIR/seal_hook_release.py" --digest-file "$ARTIFACT")
if [ "$EXPECTED_DIGEST" != "$ACTUAL_DIGEST" ] || [ "$EXPECTED_NAME" != "$(basename "$ARTIFACT")" ]; then
    printf '%s\n' "Artifact digest sidecar does not match the packaged bytes."
    exit
fi
if gh release view "$TAG" --repo wisent-ai/tama-desktop >/dev/null; then
    printf '%s\n' "Refusing to replace existing immutable GitHub release $TAG."
    exit
fi
NOTES_FILE="$RELEASE_DIR/release-notes.md"
TAMA_CHANGELOG="$DESKTOP_ROOT/CHANGELOG.md" \
TAMA_RELEASE_NOTES="$NOTES_FILE" \
TAMA_RELEASE_VERSION="$PRODUCT_VERSION" \
python3 - <<'PY'
import os
from pathlib import Path

version = os.environ["TAMA_RELEASE_VERSION"]
lines = Path(os.environ["TAMA_CHANGELOG"]).read_text().splitlines()
selected = []
collecting = False
for line in lines:
    if line.startswith(f"## {version} "):
        collecting = True
        continue
    if collecting and line.startswith("## "):
        break
    if collecting:
        selected.append(line)
if not selected:
    raise SystemExit(f"No release notes found for {version}")
Path(os.environ["TAMA_RELEASE_NOTES"]).write_text("\n".join(selected).strip() + "\n")
PY
case "$PRODUCT_VERSION" in
    *-*) CHANNEL_FLAG=--prerelease ;;
    *) CHANNEL_FLAG= ;;
esac
gh release create "$TAG" \
    "$ARTIFACT" \
    "$DIGEST_FILE" \
    "$PROVENANCE_FILE" \
    --repo wisent-ai/tama-desktop \
    --title "Tama $PRODUCT_VERSION" \
    --notes-file "$NOTES_FILE" \
    --verify-tag \
    $CHANNEL_FLAG
printf 'Published immutable release %s with digest %s\n' "$TAG" "$ACTUAL_DIGEST"
