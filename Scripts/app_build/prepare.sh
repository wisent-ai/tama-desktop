#!/bin/bash
# Sourced by build-app.sh: validate source and prepare the signed bundle inputs.
HOOKS_ROOT=${TAMA_HOOK_ROOT:-"$DESKTOP_ROOT/../tama"}
# Tama owns its hook release scripts; the app bundles a release made by them.
HOOK_RELEASE_SCRIPTS="$HOOKS_ROOT/release/hook_release"
HOOK_SOURCE_IDENTITY=$(python3 "$HOOK_RELEASE_SCRIPTS/hook_release_native/source.py" --source-root "$HOOKS_ROOT" --shell)
HOOK_SOURCE_REVISION=${HOOK_SOURCE_IDENTITY%% *}
HOOK_SOURCE_DIRTY=${HOOK_SOURCE_IDENTITY#* }
NODE_BIN=${TAMA_NODE:-}
if [ -z "$NODE_BIN" ]; then
    NODE_BIN=$(command -v node || true)
fi
if [ -z "$NODE_BIN" ] || [ ! -x "$NODE_BIN" ]; then
    printf '%s\n' "A supported Node.js executable is required to export the bundled catalog."
    false
fi
if ! "$NODE_BIN" -e 'const major = Number.parseInt(process.versions.node.split(".")[Number("0")], Number("10")); process.exit(Number.isInteger(major) && major >= Number("20") ? Number("0") : Number("1"));'; then
    printf '%s\n' "Node.js 20 or newer is required to export the bundled catalog."
    false
fi
CARGO_BIN=${TAMA_CARGO:-}
if [ -z "$CARGO_BIN" ]; then
    CARGO_BIN=$(command -v cargo || true)
fi
if [ -z "$CARGO_BIN" ] || [ ! -x "$CARGO_BIN" ]; then
    printf '%s\n' "cargo is required to build the bundled Tama backend."
    false
fi
CODESIGN_IDENTITY=${WISENT_CODESIGN_IDENTITY:-}
APP_PROVISIONING_PROFILE=${WISENT_APP_PROVISIONING_PROFILE:-}
CODESIGN_TIMESTAMP=${TAMA_CODESIGN_TIMESTAMP:---timestamp=none}
NETWORK_FILTER_PROVISIONING_PROFILE=${WISENT_NETWORK_FILTER_PROVISIONING_PROFILE:-}
if ! CODESIGN_IDENTITIES=$(security find-identity -v -p codesigning); then
    printf '%s\n' "Could not read code-signing identities from the Keychain."
    false
fi
if [ -z "$CODESIGN_IDENTITY" ]; then
    CODESIGN_IDENTITY=$(printf '%s\n' "$CODESIGN_IDENTITIES" \
        | awk -F '"' '/Apple Development:/ { print $2; exit }')
fi
if [ -z "$CODESIGN_IDENTITY" ] || [ "$CODESIGN_IDENTITY" = "-" ]; then
    printf '%s\n' "Stable Apple Development signing identity is required; refusing ad-hoc signing." >&2
    exit 1
fi
case "$CODESIGN_IDENTITY" in
    *'
'*|*'"'*)
        printf '%s\n' "Code-signing identity must be an exact certificate name or hash."
        false
        ;;
esac
CODESIGN_IDENTITY_HASH=$(printf '%s' "$CODESIGN_IDENTITY" \
    | LC_ALL=C tr '[:lower:]' '[:upper:]')
if ! printf '%s\n' "$CODESIGN_IDENTITIES" \
    | grep -F -e "\"$CODESIGN_IDENTITY\"" >/dev/null \
    && ! printf '%s\n' "$CODESIGN_IDENTITIES" \
        | LC_ALL=C tr '[:lower:]' '[:upper:]' \
        | grep -F -e ") $CODESIGN_IDENTITY_HASH \"" >/dev/null; then
    printf 'Code-signing identity is not available in the Keychain: %s\n' \
        "$CODESIGN_IDENTITY"
    false
fi
case "$BUILD_CHANNEL" in
    development|preview|stable) ;;
    *)
        printf 'Unsupported Tama build channel: %s\n' "$BUILD_CHANNEL"
        false
        ;;
esac
case "$CODESIGN_TIMESTAMP" in
    --timestamp|--timestamp=none) ;;
    *)
        printf 'Unsupported code-signing timestamp mode: %s\n' "$CODESIGN_TIMESTAMP"
        false
        ;;
esac
if [ -n "$APP_PROVISIONING_PROFILE" ] \
    && [ ! -f "$APP_PROVISIONING_PROFILE" ]; then
    printf 'Tama app provisioning profile not found: %s\n' \
        "$APP_PROVISIONING_PROFILE"
    false
fi
if [ -n "$NETWORK_FILTER_PROVISIONING_PROFILE" ] \
    && [ ! -f "$NETWORK_FILTER_PROVISIONING_PROFILE" ]; then
    printf 'Network Filter provisioning profile not found: %s\n' \
        "$NETWORK_FILTER_PROVISIONING_PROFILE"
    false
fi

swift build --package-path "$DESKTOP_ROOT" --configuration release --product Tama
BIN_DIR=$(swift build --package-path "$DESKTOP_ROOT" --configuration release --show-bin-path)
BUILD_STAGING_BUNDLE=$(mktemp -d \
    "$DESKTOP_ROOT/.build/.Tama.building.XXXXXXXX")
APP_BUNDLE="$BUILD_STAGING_BUNDLE"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"
install -m 0644 "$DESKTOP_ROOT/App/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$BUNDLE_SHORT_VERSION" "$CONTENTS/Info.plist"
plutil -replace TamaProductVersion -string "$PRODUCT_VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
# The feed URL already exists in this repository, in
# .wisent-desktop-release.json - the release manifest wisent-desktop-update
# reads. Until 2026-08-31 this script stamped SUFeedURL only from
# WISENT_UPDATE_FEED_URL, so every build that did not export that variable,
# which includes every local and source build, shipped the empty SUFeedURL that
# App/Info.plist carries. Sparkle with no feed URL issues no request, so "Check
# for Updates…" did nothing at all.
#
# The manifest is now the default, the environment variable stays an override for
# a staging feed, and a bundle that would ship without a feed URL fails the build
# instead of being discovered months later by a user who never got an update.
RELEASE_MANIFEST="$DESKTOP_ROOT/.wisent-desktop-release.json"
UPDATE_FEED_URL=${WISENT_UPDATE_FEED_URL:-}
if [ -z "$UPDATE_FEED_URL" ] && [ -f "$RELEASE_MANIFEST" ]; then
    command -v jq >/dev/null 2>&1 || {
        printf '%s\n' "jq is required to read $RELEASE_MANIFEST" >&2
        exit 1
    }
    UPDATE_FEED_URL=$(jq -r '.feed_url // empty' "$RELEASE_MANIFEST")
fi
case "$UPDATE_FEED_URL" in
    https://*) ;;
    '')
        printf '%s\n' "no update feed URL: set WISENT_UPDATE_FEED_URL, or .feed_url in $RELEASE_MANIFEST. An app with an empty SUFeedURL can never check for updates." >&2
        exit 1 ;;
    *)
        printf '%s\n' "update feed URL must use HTTPS: $UPDATE_FEED_URL" >&2
        exit 1 ;;
esac
plutil -replace SUFeedURL -string "$UPDATE_FEED_URL" "$CONTENTS/Info.plist"
install -m 0755 "$BIN_DIR/Tama" "$MACOS/Tama"
install -m 0644 \
    "$DESKTOP_ROOT/Sources/TamaDesktop/Resources/tama-first-use.json" \
    "$RESOURCES/tama-first-use.json"
SPARKLE_FRAMEWORK="$BIN_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    printf 'Sparkle.framework is unavailable: %s\n' "$SPARKLE_FRAMEWORK" >&2
    false
fi
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS/Sparkle.framework"
for resource_bundle in "$BIN_DIR"/*.bundle; do
    [ -d "$resource_bundle" ] || continue
    ditto "$resource_bundle" "$RESOURCES/$(basename "$resource_bundle")"
done
if ! otool -l "$MACOS/Tama" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$MACOS/Tama"
fi
"$NODE_BIN" "$SCRIPT_DIR/app_build/export-catalog.mjs" "$HOOKS_ROOT" "$RESOURCES/tama-catalog.json"
HOOK_RELEASE="$RESOURCES/hooks-release"
mkdir -p "$HOOK_RELEASE"
install -m 0644 "$HOOKS_ROOT/package.json" "$HOOK_RELEASE/package.json"
for directory in shared-hooks claude-hooks codex-hooks repo-githooks; do
    cp -R "$HOOKS_ROOT/$directory" "$HOOK_RELEASE/$directory"
done
find "$HOOK_RELEASE" -name '__pycache__' -type d -prune -exec rm -rf {} +
rm -f \
    "$HOOK_RELEASE/shared-hooks/generate-configs.mjs" \
    "$HOOK_RELEASE/shared-hooks/providers.json" \
    "$HOOK_RELEASE/shared-hooks/run-one-session-hook.js"

SYSTEM_POLICY_SOURCE="$DESKTOP_ROOT/SystemPolicy/macOS"
SYSTEM_POLICY_DIR="$HOOK_RELEASE/shared-hooks/system-policy"
SYSTEM_POLICY_BACKEND="$SYSTEM_POLICY_DIR/tama-system-policy-macos"
HELPER_TOOLS="$CONTENTS/Library/HelperTools"
SYSTEM_POLICY_DAEMON="$HELPER_TOOLS/tama-system-policy-daemon"
LAUNCH_DAEMONS="$CONTENTS/Library/LaunchDaemons"
SYSTEM_EXTENSION="$CONTENTS/Library/SystemExtensions/ai.wisent.tama.network-filter.systemextension"
NETWORK_FILTER_CONTENTS="$SYSTEM_EXTENSION/Contents"
NETWORK_FILTER_BINARY="$NETWORK_FILTER_CONTENTS/MacOS/tama-network-filter"
mkdir -p \
    "$SYSTEM_POLICY_DIR" \
    "$HELPER_TOOLS" \
    "$LAUNCH_DAEMONS" \
    "$NETWORK_FILTER_CONTENTS/MacOS"
