#!/bin/sh
# Sourced by build-app.sh after the hook release is sealed: writes the build
# record the app shows under Posture (BuildIdentity in Models.swift) to
# $RESOURCES/tama-build.json. It names what was built, from which source, for
# which architecture and channel, the pinned Swift dependencies and the sealed
# hook release. Package.resolved is committed, so a build without it is refused
# rather than recorded with no dependencies.
if [ ! -f "$DESKTOP_ROOT/Package.resolved" ]; then
    printf '%s\n' "Package.resolved is missing from $DESKTOP_ROOT; the build record cannot name the pinned dependencies." >&2
    false
fi
BUILD_RECORD="$RESOURCES/tama-build.json"
printf '%s\n' '{}' > "$BUILD_RECORD"
plutil -insert architecture -string "$TARGET_ARCH" "$BUILD_RECORD"
plutil -insert builtAt -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BUILD_RECORD"
plutil -insert channel -string "$BUILD_CHANNEL" "$BUILD_RECORD"
plutil -insert platform -string macOS "$BUILD_RECORD"
plutil -insert productVersion -string "$PRODUCT_VERSION" "$BUILD_RECORD"
plutil -insert schema -string ai.wisent.tama.build "$BUILD_RECORD"
plutil -insert sourceDirty -bool "$SOURCE_DIRTY" "$BUILD_RECORD"
plutil -insert sourceRevision -string "$SOURCE_REVISION" "$BUILD_RECORD"
plutil -insert dependencies -json "$(plutil -extract pins json -o - "$DESKTOP_ROOT/Package.resolved")" "$BUILD_RECORD"
plutil -insert hookRelease -json "$(cat "$HOOK_RELEASE/release.json")" "$BUILD_RECORD"
