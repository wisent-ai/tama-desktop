#!/bin/bash
# Sourced by build-app.sh: validate source and prepare the signed bundle inputs.
# The Tama checkout is the sibling of this one unless TAMA_HOOK_ROOT names
# another.
if [ -n "${TAMA_HOOK_ROOT+set}" ]; then
    HOOKS_ROOT=$TAMA_HOOK_ROOT
else
    HOOKS_ROOT="$DESKTOP_ROOT/../tama"
fi
# Node exports the bundled catalog: TAMA_NODE, else the node on PATH.
if [ -n "${TAMA_NODE+set}" ]; then
    NODE_BIN=$TAMA_NODE
elif ! NODE_BIN=$(command -v node); then
    printf '%s\n' "No node is on PATH and TAMA_NODE names none; Node.js exports the bundled catalog." >&2
    false
fi
if [ ! -x "$NODE_BIN" ]; then
    printf '%s\n' "$NODE_BIN is not an executable Node.js; it exports the bundled catalog." >&2
    false
fi
# Cargo builds the bundled Tama backend: TAMA_CARGO, else the cargo on PATH.
if [ -n "${TAMA_CARGO+set}" ]; then
    CARGO_BIN=$TAMA_CARGO
elif ! CARGO_BIN=$(command -v cargo); then
    printf '%s\n' "No cargo is on PATH and TAMA_CARGO names none; cargo builds the bundled Tama backend." >&2
    false
fi
if [ ! -x "$CARGO_BIN" ]; then
    printf '%s\n' "$CARGO_BIN is not an executable cargo; it builds the bundled Tama backend." >&2
    false
fi
# Tama packages, seals and installs its own hook release; the app bundles a
# release made by the tama program built from that checkout.
"$CARGO_BIN" build --manifest-path "$HOOKS_ROOT/rust/Cargo.toml" --locked --release -p tama-cli
TAMA_PROGRAM="$HOOKS_ROOT/rust/target/release/tama"
HOOK_SOURCE_IDENTITY=$("$TAMA_PROGRAM" hooks identity --source-root "$HOOKS_ROOT" --shell)
HOOK_SOURCE_REVISION=${HOOK_SOURCE_IDENTITY%% *}
HOOK_SOURCE_DIRTY=${HOOK_SOURCE_IDENTITY#* }
# An unnamed signing identity is chosen from the Keychain below.
CODESIGN_IDENTITY=
if [ -n "${WISENT_CODESIGN_IDENTITY+set}" ]; then
    CODESIGN_IDENTITY=$WISENT_CODESIGN_IDENTITY
fi
# Profiles are embedded only when named.
APP_PROVISIONING_PROFILE=
if [ -n "${WISENT_APP_PROVISIONING_PROFILE+set}" ]; then
    APP_PROVISIONING_PROFILE=$WISENT_APP_PROVISIONING_PROFILE
fi
NETWORK_FILTER_PROVISIONING_PROFILE=
if [ -n "${WISENT_NETWORK_FILTER_PROVISIONING_PROFILE+set}" ]; then
    NETWORK_FILTER_PROVISIONING_PROFILE=$WISENT_NETWORK_FILTER_PROVISIONING_PROFILE
fi
# A development build is signed without a secure timestamp unless
# TAMA_CODESIGN_TIMESTAMP asks for one.
if [ -n "${TAMA_CODESIGN_TIMESTAMP+set}" ]; then
    CODESIGN_TIMESTAMP=$TAMA_CODESIGN_TIMESTAMP
else
    CODESIGN_TIMESTAMP=--timestamp=none
fi
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
    false
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
install -m "$DATA_MODE" "$DESKTOP_ROOT/App/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$BUNDLE_SHORT_VERSION" "$CONTENTS/Info.plist"
plutil -replace TamaProductVersion -string "$PRODUCT_VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
# Stado resolves the deployment's update origin; source carries no host.
# WISENT_UPDATE_FEED_URL explicitly overrides it for a staging feed.
UPDATE_FEED_URL=
if [ -n "${WISENT_UPDATE_FEED_URL+set}" ]; then
    UPDATE_FEED_URL=$WISENT_UPDATE_FEED_URL
fi
if [ -z "$UPDATE_FEED_URL" ]; then
    UPDATE_FEED_URL=$(stado web origin url /api/release/appcast --query product=tama-desktop)
fi
case "$UPDATE_FEED_URL" in
    https://*) ;;
    '')
        printf '%s\n' "Stado returned no update feed URL; declare an appcast origin or set WISENT_UPDATE_FEED_URL." >&2
        false ;;
    *)
        printf '%s\n' "update feed URL must use HTTPS: $UPDATE_FEED_URL" >&2
        false ;;
esac
plutil -replace SUFeedURL -string "$UPDATE_FEED_URL" "$CONTENTS/Info.plist"
install -m "$EXECUTABLE_MODE" "$BIN_DIR/Tama" "$MACOS/Tama"
install -m "$DATA_MODE" \
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
install -m "$DATA_MODE" "$HOOKS_ROOT/package.json" "$HOOK_RELEASE/package.json"
for directory in shared-hooks claude-hooks repo-githooks; do
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
