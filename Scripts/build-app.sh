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
. "$SCRIPT_DIR/app_build/prepare.sh"
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
    "$SYSTEM_POLICY_SOURCE/Bundle/TamaNetworkFilter-Info.plist" \
    "$NETWORK_FILTER_CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$BUNDLE_SHORT_VERSION" "$NETWORK_FILTER_CONTENTS/Info.plist"
plutil -replace TamaProductVersion -string "$PRODUCT_VERSION" "$NETWORK_FILTER_CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$NETWORK_FILTER_CONTENTS/Info.plist"
install -m 0644 \
    "$SYSTEM_POLICY_SOURCE/Bundle/ai.wisent.tama.system-policy.plist" \
    "$LAUNCH_DAEMONS/ai.wisent.tama.system-policy.plist"
for executable in "$SYSTEM_POLICY_BACKEND" "$SYSTEM_POLICY_DAEMON"; do
    codesign \
        --force \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        $CODESIGN_TIMESTAMP \
        --entitlements "$SYSTEM_POLICY_SOURCE/Bundle/TamaSystemPolicy.entitlements" \
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
    --entitlements "$SYSTEM_POLICY_SOURCE/Bundle/TamaNetworkFilter.entitlements" \
    "$SYSTEM_EXTENSION"
codesign --verify --strict "$SYSTEM_EXTENSION"
# Package every native hook command declared by the registry together with the
# desktop's Rust CLI and MCP server. The shared packager resolves Cargo targets
# and artifact paths from cargo metadata, signs every executable, and records
# the exact packaged set before the release is sealed.
python3 "$SCRIPT_DIR/hook_release/stage_live_hook_release.py" \
    --source-root "$HOOKS_ROOT" \
    --release-root "$HOOK_RELEASE" \
    --cargo "$CARGO_BIN" \
    --include-bin tama-cli \
    --include-bin tama-mcp-server \
    --codesign-identity "$CODESIGN_IDENTITY" \
    --codesign-timestamp="$CODESIGN_TIMESTAMP" \
    >/dev/null
TAMA_HOOK_SOURCE_DIRTY="$HOOK_SOURCE_DIRTY" \
TAMA_HOOK_SOURCE_REVISION="$HOOK_SOURCE_REVISION" \
python3 "$SCRIPT_DIR/hook_release/seal_hook_release.py" --source-root "$HOOKS_ROOT" "$HOOK_RELEASE" >/dev/null
install -m 0755 "$SCRIPT_DIR/emergency_disable_hooks" "$RESOURCES/emergency_disable_hooks"
install -m 0755 "$SCRIPT_DIR/install_hook_release.py" "$RESOURCES/install_hook_release.py"
# The installer imports its parts from its own folder, so they ship beside it,
# source only: a cache written here would change the signed bundle.
rm -rf "$RESOURCES/install_hook_release_parts"
ditto "$SCRIPT_DIR/install_hook_release_parts" "$RESOURCES/install_hook_release_parts"
find "$RESOURCES/install_hook_release_parts" -name __pycache__ -prune -exec rm -rf {} +
if [ -f "$DESKTOP_ROOT/App/AppIcon.icns" ]; then
    install -m 0644 "$DESKTOP_ROOT/App/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
    sh "$SCRIPT_DIR/app_build/import-brand-icon.sh" tama-desktop "$RESOURCES/AppIcon.icns"
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
IDENTITY_BUILD_DIR="$DESKTOP_ROOT/.build/identity-helper"
swift build --package-path "$DESKTOP_ROOT/.build/checkouts/wisent-desktop-auth" \
    --configuration release --product wisent-identity-keychain-helper --scratch-path "$IDENTITY_BUILD_DIR"
mkdir -p "$(dirname "$IDENTITY_HELPER")"
install -m 0755 "$IDENTITY_BUILD_DIR/release/wisent-identity-keychain-helper" "$IDENTITY_HELPER"
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
