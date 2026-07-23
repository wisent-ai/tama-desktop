#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP_BUNDLE="$DESKTOP_ROOT/.build/Tama.app"
INSTALLED_BUNDLE=${TAMA_INSTALL_APP_PATH:-"$HOME/Applications/Tama.app"}
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

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
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
HOOKS_ROOT=${TAMA_REPOSITORY_ROOT:-"$DESKTOP_ROOT/../hooks-rotator"}
NODE_BIN=${TAMA_NODE:-}
if [ -z "$NODE_BIN" ]; then
    NODE_BIN=$(command -v node)
fi
CODESIGN_IDENTITY=${WISENT_CODESIGN_IDENTITY:-}
APP_PROVISIONING_PROFILE=${WISENT_APP_PROVISIONING_PROFILE:-}
NETWORK_FILTER_PROVISIONING_PROFILE=${WISENT_NETWORK_FILTER_PROVISIONING_PROFILE:-}
if [ -z "$CODESIGN_IDENTITY" ]; then
    CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F '"' '/Apple Development:/ { print $2; exit }')
fi
if [ -z "$CODESIGN_IDENTITY" ] || [ "$CODESIGN_IDENTITY" = "-" ]; then
    printf '%s\n' "Stable Apple Development signing identity is required; refusing ad-hoc signing." >&2
    exit 1
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
rm -f \
    "$HOOK_RELEASE/shared-hooks/generate-configs.mjs" \
    "$HOOK_RELEASE/shared-hooks/omp-shared-hooks.js" \
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
install -m 0644 \
    "$SYSTEM_POLICY_SOURCE/ai.wisent.tama.system-policy.plist" \
    "$LAUNCH_DAEMONS/ai.wisent.tama.system-policy.plist"
for executable in "$SYSTEM_POLICY_BACKEND" "$SYSTEM_POLICY_DAEMON"; do
    codesign \
        --force \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        --timestamp=none \
        --entitlements "$SYSTEM_POLICY_SOURCE/TamaSystemPolicy.entitlements" \
        "$executable"
    codesign --verify --strict "$executable"
done
if [ -n "$NETWORK_FILTER_PROVISIONING_PROFILE" ]; then
    if [ ! -f "$NETWORK_FILTER_PROVISIONING_PROFILE" ]; then
        printf 'Network Filter provisioning profile not found: %s\n' \
            "$NETWORK_FILTER_PROVISIONING_PROFILE" >&2
        exit 1
    fi
    install -m 0644 \
        "$NETWORK_FILTER_PROVISIONING_PROFILE" \
        "$NETWORK_FILTER_CONTENTS/embedded.provisionprofile"
fi
codesign \
    --force \
    --sign "$CODESIGN_IDENTITY" \
    --identifier ai.wisent.tama.network-filter \
    --options runtime \
    --timestamp=none \
    --entitlements "$SYSTEM_POLICY_SOURCE/TamaNetworkFilter.entitlements" \
    "$SYSTEM_EXTENSION"
codesign --verify --strict "$SYSTEM_EXTENSION"
python3 "$SCRIPT_DIR/seal_hook_release.py" "$HOOK_RELEASE" >/dev/null
install -m 0755 "$SCRIPT_DIR/emergency_disable_hooks" "$RESOURCES/emergency_disable_hooks"
install -m 0755 "$SCRIPT_DIR/install_hook_release.py" "$RESOURCES/install_hook_release.py"
sh "$SCRIPT_DIR/import-brand-icon.sh" tama-desktop "$RESOURCES/AppIcon.icns"
if [ -n "$APP_PROVISIONING_PROFILE" ]; then
    if [ ! -f "$APP_PROVISIONING_PROFILE" ]; then
        printf 'Tama app provisioning profile not found: %s\n' \
            "$APP_PROVISIONING_PROFILE" >&2
        exit 1
    fi
    install -m 0644 \
        "$APP_PROVISIONING_PROFILE" \
        "$CONTENTS/embedded.provisionprofile"
    codesign \
        --force \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        --timestamp=none \
        --entitlements "$DESKTOP_ROOT/App/TamaDesktop.entitlements" \
        "$APP_BUNDLE"
else
    codesign \
        --force \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        --timestamp=none \
        "$APP_BUNDLE"
fi
codesign --verify --strict --deep "$APP_BUNDLE"
printf 'Built %s\n' "$APP_BUNDLE"
rm -rf "$INSTALLED_BUNDLE"
mkdir -p "$(dirname "$INSTALLED_BUNDLE")"
ditto "$APP_BUNDLE" "$INSTALLED_BUNDLE"
codesign --verify --strict --deep "$INSTALLED_BUNDLE"
unregister_bundle "$APP_BUNDLE"
"$LSREGISTER" -f "$INSTALLED_BUNDLE"
printf 'Installed %s\n' "$INSTALLED_BUNDLE"
RESTART_APP=${WISENT_RESTART_APP:-"$SCRIPT_DIR/wisent-restart-app"}
if [ "${WISENT_RESTART_AFTER_BUILD:-1}" != 0 ] && [ -x "$RESTART_APP" ]; then
    "$RESTART_APP" --if-running "$INSTALLED_BUNDLE"
fi
