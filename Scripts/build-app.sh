#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_BUNDLE="$DESKTOP_ROOT/.build/Tama.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
HOOKS_ROOT=${TAMA_REPOSITORY_ROOT:-"$DESKTOP_ROOT/../hooks-rotator"}
NODE_BIN=${TAMA_NODE:-}
if [ -z "$NODE_BIN" ]; then
    NODE_BIN=$(command -v node)
fi

swift build --package-path "$DESKTOP_ROOT" --configuration release --product Tama
BIN_DIR=$(swift build --package-path "$DESKTOP_ROOT" --configuration release --show-bin-path)

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"
install -m 0644 "$DESKTOP_ROOT/App/Info.plist" "$CONTENTS/Info.plist"
install -m 0755 "$BIN_DIR/Tama" "$MACOS/Tama"
"$NODE_BIN" "$SCRIPT_DIR/export-catalog.mjs" "$HOOKS_ROOT" "$RESOURCES/tama-catalog.json"
HOOK_RELEASE="$RESOURCES/hooks-release"
mkdir -p "$HOOK_RELEASE"
install -m 0644 "$HOOKS_ROOT/package.json" "$HOOK_RELEASE/package.json"
for directory in shared-hooks claude-hooks codex-hooks repo-githooks; do
    cp -R "$HOOKS_ROOT/$directory" "$HOOK_RELEASE/$directory"
done
python3 "$SCRIPT_DIR/seal_hook_release.py" "$HOOK_RELEASE" >/dev/null
install -m 0755 "$SCRIPT_DIR/emergency_disable_hooks" "$RESOURCES/emergency_disable_hooks"
install -m 0755 "$SCRIPT_DIR/install_hook_release.py" "$RESOURCES/install_hook_release.py"
if [ -n "${WISENT_GROUND_TRUTH_API:-${GROUND_TRUTH_API:-}}" ]; then
    sh "$SCRIPT_DIR/import-brand-icon.sh" tama-desktop "$RESOURCES/AppIcon.icns"
else
    printf '%s\n' "Skipping AppIcon import: canonical asset resolver is not configured." >&2
fi
CODESIGN_IDENTITY=${WISENT_CODESIGN_IDENTITY:-}
if [ -z "$CODESIGN_IDENTITY" ]; then
    CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F '"' '/Apple Development:/ { print $2; exit }')
fi
if [ -z "$CODESIGN_IDENTITY" ] || [ "$CODESIGN_IDENTITY" = "-" ]; then
    printf '%s\n' "Stable Apple Development signing identity is required; refusing ad-hoc signing." >&2
    exit 1
fi
codesign --force --deep --sign "$CODESIGN_IDENTITY" --timestamp=none "$APP_BUNDLE"
codesign --verify --strict --deep "$APP_BUNDLE"
printf 'Built %s\n' "$APP_BUNDLE"

RESTART_APP=${WISENT_RESTART_APP:-"$SCRIPT_DIR/wisent-restart-app"}
if [ "${WISENT_RESTART_AFTER_BUILD:-1}" != 0 ] && [ -x "$RESTART_APP" ]; then
    "$RESTART_APP" --if-running "$APP_BUNDLE"
fi
