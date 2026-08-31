#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
FINAL_APP_BUNDLE="$DESKTOP_ROOT/.build/Tama.app"
INSTALLED_BUNDLE=${TAMA_INSTALL_APP_PATH:-"$HOME/Applications/Tama.app"}
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
PRODUCT_VERSION=${TAMA_RELEASE_VERSION:-${WISENT_RELEASE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DESKTOP_ROOT/App/Info.plist")}}
BUNDLE_SHORT_VERSION=${PRODUCT_VERSION%%[-+]*}
if ! printf '%s\n' "$BUNDLE_SHORT_VERSION" | LC_ALL=C grep -Eq '^[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+$'; then
    printf '%s\n' "The Apple bundle version derived from $PRODUCT_VERSION is invalid."
    false
fi
BUILD_CHANNEL=${TAMA_BUILD_CHANNEL:-development}
SOURCE_REVISION=$(git -C "$DESKTOP_ROOT" rev-parse HEAD)
BUILD_NUMBER=${WISENT_BUILD_NUMBER:-$(git -C "$DESKTOP_ROOT" rev-list --count HEAD)}
TARGET_ARCH=$(uname -m)
SOURCE_DIRTY=false
if [ -n "$(git -C "$DESKTOP_ROOT" status --porcelain --untracked-files=normal)" ]; then
    SOURCE_DIRTY=true
fi

BUILD_STAGING_BUNDLE=
INSTALL_STAGING_BUNDLE=
PROMOTION_BACKUP=
PROMOTION_BACKUP_ROOT=
PROMOTION_SOURCE=
PROMOTION_TARGET=

cleanup_staging() {
    status=$?
    if [ -n "$PROMOTION_BACKUP" ] && [ ! -e "$PROMOTION_TARGET" ]; then
        if mv "$PROMOTION_BACKUP" "$PROMOTION_TARGET"; then
            PROMOTION_BACKUP=
            rm -rf "$PROMOTION_BACKUP_ROOT"
            PROMOTION_BACKUP_ROOT=
        else
            printf 'Previous bundle requires manual recovery from %s\n' \
                "$PROMOTION_BACKUP"
        fi
    fi
    if [ -n "$BUILD_STAGING_BUNDLE" ]; then
        rm -rf "$BUILD_STAGING_BUNDLE" || true
    fi
    if [ -n "$INSTALL_STAGING_BUNDLE" ]; then
        rm -rf "$INSTALL_STAGING_BUNDLE" || true
    fi
    return "$status"
}

promote_bundle() {
    PROMOTION_BACKUP_ROOT=$(mktemp -d \
        "$(dirname "$PROMOTION_TARGET")/.Tama.previous.XXXXXXXX")
    PROMOTION_BACKUP="$PROMOTION_BACKUP_ROOT/bundle"
    if [ -e "$PROMOTION_TARGET" ]; then
        if ! mv "$PROMOTION_TARGET" "$PROMOTION_BACKUP"; then
            rm -rf "$PROMOTION_BACKUP_ROOT"
            PROMOTION_BACKUP_ROOT=
            PROMOTION_BACKUP=
            false
        fi
    else
        PROMOTION_BACKUP=
    fi
    if mv "$PROMOTION_SOURCE" "$PROMOTION_TARGET"; then
        rm -rf "$PROMOTION_BACKUP_ROOT"
        PROMOTION_BACKUP_ROOT=
        PROMOTION_BACKUP=
        return
    fi
    if [ -n "$PROMOTION_BACKUP" ]; then
        if mv "$PROMOTION_BACKUP" "$PROMOTION_TARGET"; then
            PROMOTION_BACKUP=
            rm -rf "$PROMOTION_BACKUP_ROOT"
            PROMOTION_BACKUP_ROOT=
        else
            printf 'Previous bundle requires manual recovery from %s\n' \
                "$PROMOTION_BACKUP"
        fi
    else
        rm -rf "$PROMOTION_BACKUP_ROOT"
        PROMOTION_BACKUP_ROOT=
    fi
    false
}

trap cleanup_staging EXIT

unregister_bundle() {
    if output=$("$LSREGISTER" -u "$1" 2>&1); then
        return 0
    fi
    case "$output" in
        *-10814*) return 0 ;;
    esac
    printf '%s\n' "$output" >&2
    return 1
}
HOOKS_ROOT=${TAMA_HOOK_ROOT:-"$DESKTOP_ROOT/../tama"}
if ! HOOK_SOURCE_REVISION=$(git -C "$HOOKS_ROOT" rev-parse HEAD); then
    printf '%s\n' "Tama hook source is unavailable at $HOOKS_ROOT; set TAMA_HOOK_ROOT for a developer build."
    false
fi
HOOK_SOURCE_DIRTY=false
if [ -n "$(git -C "$HOOKS_ROOT" status --porcelain --untracked-files=normal)" ]; then
    HOOK_SOURCE_DIRTY=true
fi
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
"$NODE_BIN" "$SCRIPT_DIR/export-catalog.mjs" "$HOOKS_ROOT" "$RESOURCES/tama-catalog.json"
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
xcrun --sdk macosx clang \
    -fobjc-arc \
    -O2 \
    -mmacosx-version-min=14.0 \
    -framework Foundation \
    "$SYSTEM_POLICY_SOURCE/tama-system-policy-macos.m" \
    -o "$SYSTEM_POLICY_BACKEND"
xcrun --sdk macosx clang \
    -fobjc-arc \
    -O2 \
    -mmacosx-version-min=14.0 \
    -framework Foundation \
    -lEndpointSecurity \
    -lbsm \
    "$SYSTEM_POLICY_SOURCE/tama-system-policy-daemon.m" \
    -o "$SYSTEM_POLICY_DAEMON"
xcrun --sdk macosx clang \
    -fobjc-arc \
    -fapplication-extension \
    -O2 \
    -mmacosx-version-min=14.0 \
    -framework Foundation \
    -framework Network \
    -framework NetworkExtension \
    -lbsm \
    "$SYSTEM_POLICY_SOURCE/TamaNetworkFilter.m" \
    -o "$NETWORK_FILTER_BINARY"
install -m 0644 \
    "$SYSTEM_POLICY_SOURCE/TamaNetworkFilter-Info.plist" \
    "$NETWORK_FILTER_CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$BUNDLE_SHORT_VERSION" "$NETWORK_FILTER_CONTENTS/Info.plist"
plutil -replace TamaProductVersion -string "$PRODUCT_VERSION" "$NETWORK_FILTER_CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$NETWORK_FILTER_CONTENTS/Info.plist"
install -m 0644 \
    "$SYSTEM_POLICY_SOURCE/ai.wisent.tama.system-policy.plist" \
    "$LAUNCH_DAEMONS/ai.wisent.tama.system-policy.plist"
for executable in "$SYSTEM_POLICY_BACKEND" "$SYSTEM_POLICY_DAEMON"; do
    codesign \
        --force \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        $CODESIGN_TIMESTAMP \
        --entitlements "$SYSTEM_POLICY_SOURCE/TamaSystemPolicy.entitlements" \
        "$executable"
    codesign --verify --strict "$executable"
done
if [ -n "$NETWORK_FILTER_PROVISIONING_PROFILE" ]; then
    install -m 0644 \
        "$NETWORK_FILTER_PROVISIONING_PROFILE" \
        "$NETWORK_FILTER_CONTENTS/embedded.provisionprofile"
fi
codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --identifier ai.wisent.tama.network-filter \
    --options runtime \
    $CODESIGN_TIMESTAMP \
    --entitlements "$SYSTEM_POLICY_SOURCE/TamaNetworkFilter.entitlements" \
    "$SYSTEM_EXTENSION"
codesign --verify --strict "$SYSTEM_EXTENSION"
# The desktop spawns the sealed Rust CLI once as its loopback backend, and
# the MCP snippet names the server next to it. Both ship inside the release
# so the binary the app runs is the one this build sealed.
"$CARGO_BIN" build \
    --release \
    --manifest-path "$HOOKS_ROOT/rust/Cargo.toml" \
    -p tama-cli \
    -p tama-mcp-server
mkdir -p "$HOOK_RELEASE/bin"
install -m 0755 \
    "$HOOKS_ROOT/rust/target/release/tama-cli" \
    "$HOOK_RELEASE/bin/tama-cli"
install -m 0755 \
    "$HOOKS_ROOT/rust/target/release/tama-mcp-server" \
    "$HOOK_RELEASE/bin/tama-mcp-server"
for executable in "$HOOK_RELEASE/bin/tama-cli" "$HOOK_RELEASE/bin/tama-mcp-server"; do
    codesign \
        --force \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        $CODESIGN_TIMESTAMP \
        "$executable"
    codesign --verify --strict "$executable"
done
TAMA_HOOK_SOURCE_DIRTY="$HOOK_SOURCE_DIRTY" \
TAMA_HOOK_SOURCE_REVISION="$HOOK_SOURCE_REVISION" \
python3 "$SCRIPT_DIR/seal_hook_release.py" "$HOOK_RELEASE" >/dev/null
install -m 0755 "$SCRIPT_DIR/emergency_disable_hooks" "$RESOURCES/emergency_disable_hooks"
install -m 0755 "$SCRIPT_DIR/install_hook_release.py" "$RESOURCES/install_hook_release.py"
if [ -f "$DESKTOP_ROOT/App/AppIcon.icns" ]; then
    install -m 0644 "$DESKTOP_ROOT/App/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
    sh "$SCRIPT_DIR/import-brand-icon.sh" tama-desktop "$RESOURCES/AppIcon.icns"
fi
TAMA_BUILD_DEPENDENCIES="$DESKTOP_ROOT/Package.resolved" \
TAMA_BUILD_HOOK_RELEASE="$HOOK_RELEASE/release.json" \
TAMA_BUILD_CHANNEL="$BUILD_CHANNEL" \
TAMA_BUILD_DIRTY="$SOURCE_DIRTY" \
TAMA_BUILD_REVISION="$SOURCE_REVISION" \
TAMA_BUILD_TARGET_ARCH="$TARGET_ARCH" \
TAMA_BUILD_VERSION="$PRODUCT_VERSION" \
python3 - "$RESOURCES/tama-build.json" <<'PY'
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys

manifest = {
    "architecture": os.environ["TAMA_BUILD_TARGET_ARCH"],
    "builtAt": datetime.now(timezone.utc).isoformat(),
    "channel": os.environ["TAMA_BUILD_CHANNEL"],
    "platform": "macOS",
    "productVersion": os.environ["TAMA_BUILD_VERSION"],
    "schema": "ai.wisent.tama.build",
    "sourceDirty": os.environ["TAMA_BUILD_DIRTY"] == "true",
    "sourceRevision": os.environ["TAMA_BUILD_REVISION"],
}
resolved = Path(os.environ["TAMA_BUILD_DEPENDENCIES"])
manifest["dependencies"] = (
    json.loads(resolved.read_text()).get("pins", [])
    if resolved.is_file()
    else []
)
manifest["hookRelease"] = json.loads(
    Path(os.environ["TAMA_BUILD_HOOK_RELEASE"]).read_text()
)
target = next(argument for argument in sys.argv if argument != "-")
Path(target).write_text(
    json.dumps(manifest, indent=len("  "), sort_keys=True) + "\n"
)
PY
codesign \
    --force \
    --deep \
    --sign "$CODESIGN_IDENTITY" \
    --options runtime \
    $CODESIGN_TIMESTAMP \
    "$FRAMEWORKS/Sparkle.framework"
IDENTITY_HELPER="$CONTENTS/Helpers/WisentIdentityKeychainHelper"
"$DESKTOP_ROOT/.build/checkouts/wisent-desktop-auth/scripts/build-keychain-helper.sh" "$IDENTITY_HELPER"
codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --options runtime \
    $CODESIGN_TIMESTAMP \
    --identifier ai.wisent.identity.keychain-helper \
    "$IDENTITY_HELPER"
if [ -n "$APP_PROVISIONING_PROFILE" ]; then
    install -m 0644 \
        "$APP_PROVISIONING_PROFILE" \
        "$CONTENTS/embedded.provisionprofile"
    codesign \
        --force \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        $CODESIGN_TIMESTAMP \
        --entitlements "$DESKTOP_ROOT/App/TamaDesktop.entitlements" \
        "$APP_BUNDLE"
else
    codesign \
        --force \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        $CODESIGN_TIMESTAMP \
        "$APP_BUNDLE"
fi
codesign --verify --strict --deep "$APP_BUNDLE"
PROMOTION_SOURCE="$APP_BUNDLE"
PROMOTION_TARGET="$FINAL_APP_BUNDLE"
promote_bundle
BUILD_STAGING_BUNDLE=
APP_BUNDLE="$FINAL_APP_BUNDLE"
printf 'Built %s\n' "$APP_BUNDLE"
if [ "${TAMA_INSTALL_AFTER_BUILD:-yes}" = no ]; then
    exit
fi
mkdir -p "$(dirname "$INSTALLED_BUNDLE")"
INSTALL_STAGING_BUNDLE=$(mktemp -d \
    "$(dirname "$INSTALLED_BUNDLE")/.Tama.installing.XXXXXXXX")
ditto "$APP_BUNDLE" "$INSTALL_STAGING_BUNDLE"
codesign --verify --strict --deep "$INSTALL_STAGING_BUNDLE"
PROMOTION_SOURCE="$INSTALL_STAGING_BUNDLE"
PROMOTION_TARGET="$INSTALLED_BUNDLE"
promote_bundle
INSTALL_STAGING_BUNDLE=
unregister_bundle "$APP_BUNDLE"
"$LSREGISTER" -f "$INSTALLED_BUNDLE"
printf 'Installed %s\n' "$INSTALLED_BUNDLE"
RESTART_APP=${WISENT_RESTART_APP:-"$SCRIPT_DIR/wisent-restart-app"}
if [ "${WISENT_RESTART_AFTER_BUILD:-1}" != 0 ] && [ -x "$RESTART_APP" ]; then
    "$RESTART_APP" --if-running "$INSTALLED_BUNDLE"
fi
