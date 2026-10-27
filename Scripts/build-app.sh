#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
FINAL_APP_BUNDLE="$DESKTOP_ROOT/.build/Tama.app"
# Where the operator launches the app from: ~/Applications unless
# TAMA_INSTALL_APP_PATH names another place.
if [ -n "${TAMA_INSTALL_APP_PATH+set}" ]; then
    INSTALLED_BUNDLE=$TAMA_INSTALL_APP_PATH
else
    INSTALLED_BUNDLE="$HOME/Applications/Tama.app"
fi
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Installed files: data readable by everyone and writable by its owner;
# executables additionally executable by everyone.
DATA_MODE=u=rw,go=r
EXECUTABLE_MODE=u=rwx,go=rx
# The product version is Tama's own release version, else the shared release
# version, else the one App/Info.plist declares.
if [ -n "${TAMA_RELEASE_VERSION+set}" ]; then
    PRODUCT_VERSION=$TAMA_RELEASE_VERSION
elif [ -n "${WISENT_RELEASE_VERSION+set}" ]; then
    PRODUCT_VERSION=$WISENT_RELEASE_VERSION
else
    PRODUCT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DESKTOP_ROOT/App/Info.plist")
fi
BUNDLE_SHORT_VERSION=${PRODUCT_VERSION%%[-+]*}
if ! printf '%s\n' "$BUNDLE_SHORT_VERSION" | LC_ALL=C grep -Eq '^[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+$'; then
    printf '%s\n' "The Apple bundle version derived from $PRODUCT_VERSION is invalid."
    false
fi
# Every compiled component targets the macOS release the app declares.
DEPLOYMENT_TARGET=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$DESKTOP_ROOT/App/Info.plist")
# https://clang.llvm.org/docs/CommandGuide/clang.html#cmdoption-O0 — the level that enables most optimizations.
CLANG_OPTIMIZATION=-O2
# The channel is development unless TAMA_BUILD_CHANNEL names another.
if [ -n "${TAMA_BUILD_CHANNEL+set}" ]; then
    BUILD_CHANNEL=$TAMA_BUILD_CHANNEL
else
    BUILD_CHANNEL=development
fi
# A release worker builds an unpacked git archive, which has no repository to
# ask: the release names its commit in WISENT_SOURCE_COMMIT, and an archive of
# a commit is clean by construction. A local checkout is asked directly.
if [ -n "${WISENT_SOURCE_COMMIT+set}" ] && [ ! -e "$DESKTOP_ROOT/.git" ]; then
    SOURCE_REVISION=$WISENT_SOURCE_COMMIT
    SOURCE_DIRTY=false
else
    SOURCE_REVISION=$(git -C "$DESKTOP_ROOT" rev-parse HEAD)
    SOURCE_DIRTY=false
    if [ -n "$(git -C "$DESKTOP_ROOT" status --porcelain --untracked-files=normal)" ]; then
        SOURCE_DIRTY=true
    fi
fi
# The build number is the release's, else the count of commits.
if [ -n "${WISENT_BUILD_NUMBER+set}" ]; then
    BUILD_NUMBER=$WISENT_BUILD_NUMBER
else
    BUILD_NUMBER=$(git -C "$DESKTOP_ROOT" rev-list --count HEAD)
fi
TARGET_ARCH=$(uname -m)

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
        rm -rf "$BUILD_STAGING_BUNDLE"
    fi
    if [ -n "$INSTALL_STAGING_BUNDLE" ]; then
        rm -rf "$INSTALL_STAGING_BUNDLE"
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

. "$SCRIPT_DIR/app_build/prepare.sh"
xcrun --sdk macosx clang \
    -fobjc-arc \
    "$CLANG_OPTIMIZATION" \
    -mmacosx-version-min="$DEPLOYMENT_TARGET" \
    -framework Foundation \
    "$SYSTEM_POLICY_SOURCE/tama-system-policy-macos.m" \
    -o "$SYSTEM_POLICY_BACKEND"
xcrun --sdk macosx clang \
    -fobjc-arc \
    "$CLANG_OPTIMIZATION" \
    -mmacosx-version-min="$DEPLOYMENT_TARGET" \
    -framework Foundation \
    -lEndpointSecurity \
    -lbsm \
    "$SYSTEM_POLICY_SOURCE/tama-system-policy-daemon.m" \
    -o "$SYSTEM_POLICY_DAEMON"
xcrun --sdk macosx clang \
    -fobjc-arc \
    -fapplication-extension \
    "$CLANG_OPTIMIZATION" \
    -mmacosx-version-min="$DEPLOYMENT_TARGET" \
    -framework Foundation \
    -framework Network \
    -framework NetworkExtension \
    -lbsm \
    "$SYSTEM_POLICY_SOURCE/TamaNetworkFilter.m" \
    -o "$NETWORK_FILTER_BINARY"
install -m "$DATA_MODE" \
    "$SYSTEM_POLICY_SOURCE/Bundle/TamaNetworkFilter-Info.plist" \
    "$NETWORK_FILTER_CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$BUNDLE_SHORT_VERSION" "$NETWORK_FILTER_CONTENTS/Info.plist"
plutil -replace TamaProductVersion -string "$PRODUCT_VERSION" "$NETWORK_FILTER_CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$NETWORK_FILTER_CONTENTS/Info.plist"
install -m "$DATA_MODE" \
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
    install -m "$DATA_MODE" \
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
# Package the one `tama` program the registry runs every native hook through:
# the hooks, the engine and the MCP server are its subcommands. The shared
# packager resolves the Cargo target and artifact path from cargo metadata,
# signs the executable, and records the exact packaged set before the release
# is sealed.
"$TAMA_PROGRAM" hooks stage \
    --source-root "$HOOKS_ROOT" \
    --release-root "$HOOK_RELEASE" \
    --cargo "$CARGO_BIN" \
    --codesign-identity "$CODESIGN_IDENTITY" \
    --codesign-timestamp="$CODESIGN_TIMESTAMP" \
    >/dev/null
TAMA_HOOK_SOURCE_DIRTY="$HOOK_SOURCE_DIRTY" \
TAMA_HOOK_SOURCE_REVISION="$HOOK_SOURCE_REVISION" \
"$TAMA_PROGRAM" hooks seal --source-root "$HOOKS_ROOT" "$HOOK_RELEASE" >/dev/null
# The release's own bin/tama is its installer (`tama hooks install-release`).
install -m "$EXECUTABLE_MODE" "$SCRIPT_DIR/emergency_disable_hooks" "$RESOURCES/emergency_disable_hooks"
if [ -f "$DESKTOP_ROOT/App/AppIcon.icns" ]; then
    install -m "$DATA_MODE" "$DESKTOP_ROOT/App/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
    sh "$SCRIPT_DIR/app_build/import-brand-icon.sh" tama-desktop "$RESOURCES/AppIcon.icns"
fi
. "$SCRIPT_DIR/app_build/record.sh"
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
install -m "$EXECUTABLE_MODE" "$IDENTITY_BUILD_DIR/release/wisent-identity-keychain-helper" "$IDENTITY_HELPER"
codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --options runtime \
    $CODESIGN_TIMESTAMP \
    --identifier ai.wisent.identity.keychain-helper \
    "$IDENTITY_HELPER"
if [ -n "$APP_PROVISIONING_PROFILE" ]; then
    install -m "$DATA_MODE" \
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
# The build installs unless TAMA_INSTALL_AFTER_BUILD says no.
if [ -n "${TAMA_INSTALL_AFTER_BUILD+set}" ] && [ "$TAMA_INSTALL_AFTER_BUILD" = no ]; then
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
# While the .build copy stays registered it competes for the app's sign-in URL
# scheme with the installed copy, so it is unregistered. `lsregister -u` also
# exits non-zero over the Spotlight importer's own failure to scan the .build
# copy, after the installed copy is already in place; that failure is said,
# with lsregister's own output left visible above, and the installed copy is
# still registered and restarted.
if ! "$LSREGISTER" -u "$APP_BUNDLE"; then
    printf '%s\n' "lsregister did not unregister $APP_BUNDLE (its output above says why); registering the installed copy anyway." >&2
fi
"$LSREGISTER" -f "$INSTALLED_BUNDLE"
printf 'Installed %s\n' "$INSTALLED_BUNDLE"
# Stado owns the restart: a running copy is restarted on the bytes just
# installed, a stopped one stays stopped.
stado product restart --if-running "$INSTALLED_BUNDLE"
