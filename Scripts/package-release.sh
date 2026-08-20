#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
HOOKS_ROOT=${TAMA_HOOK_ROOT:-"$DESKTOP_ROOT/../tama"}
if [ ! -f "$DESKTOP_ROOT/Package.resolved" ]; then
    printf '%s\n' "A committed Package.resolved is required for release."
    false
fi
TAG=${TAMA_RELEASE_TAG:-}
if [ -z "$TAG" ]; then
    RELEASE_TAGS=$(git -C "$DESKTOP_ROOT" tag --points-at HEAD --list 'v*')
    case "$RELEASE_TAGS" in
        *'
'*)
            printf '%s\n' "More than one release tag points to HEAD; set TAMA_RELEASE_TAG explicitly."
            false
            ;;
        *) TAG=$RELEASE_TAGS ;;
    esac
fi
case "$TAG" in
    v*) PRODUCT_VERSION=${TAG#v} ;;
    *) printf '%s\n' "Release commit must have an exact signed v<SemVer> tag."; false ;;
esac
SEMVER_CORE='(0|[1-9][0-9]*)'
SEMVER_PRERELEASE_IDENTIFIER='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
SEMVER_PATTERN="^${SEMVER_CORE}\.${SEMVER_CORE}\.${SEMVER_CORE}(-${SEMVER_PRERELEASE_IDENTIFIER}(\.${SEMVER_PRERELEASE_IDENTIFIER})*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"
BUNDLE_SHORT_VERSION=${PRODUCT_VERSION%%[-+]*}
VERSION_WITHOUT_BUILD=${PRODUCT_VERSION%%+*}
if ! printf '%s\n' "$PRODUCT_VERSION" | LC_ALL=C grep -Eq "$SEMVER_PATTERN"; then
    printf '%s\n' "Release tag is not valid Semantic Versioning: $TAG"
    false
fi
if [ -n "$(git -C "$DESKTOP_ROOT" status --porcelain --untracked-files=normal)" ]; then
    printf '%s\n' "Release checkout must be clean."
    false
fi
if [ -n "$(git -C "$HOOKS_ROOT" status --porcelain --untracked-files=normal)" ]; then
    printf '%s\n' "The bundled hook source checkout must be clean."
    false
fi
git -C "$DESKTOP_ROOT" verify-tag "$TAG"
if [ "$(git -C "$DESKTOP_ROOT" rev-parse "$TAG^{}")" != "$(git -C "$DESKTOP_ROOT" rev-parse HEAD)" ]; then
    printf '%s\n' "Selected release tag does not resolve to HEAD: $TAG"
    false
fi
if ! grep -F "## $PRODUCT_VERSION —" "$DESKTOP_ROOT/CHANGELOG.md" >/dev/null; then
    printf '%s\n' "CHANGELOG.md has no section for $PRODUCT_VERSION."
    false
fi
if grep -F "## $PRODUCT_VERSION — Unreleased" "$DESKTOP_ROOT/CHANGELOG.md" >/dev/null; then
    printf '%s\n' "Replace the Unreleased heading before packaging."
    false
fi
: "${WISENT_CODESIGN_IDENTITY:?Set the dedicated release signing identity.}"
: "${WISENT_APP_PROVISIONING_PROFILE:?Set the app provisioning profile.}"
: "${WISENT_NETWORK_FILTER_PROVISIONING_PROFILE:?Set the Network Extension provisioning profile.}"
NOTARY_PROFILE=${WISENT_NOTARY_PROFILE:-}
if [ -z "$NOTARY_PROFILE" ]; then
    printf '%s\n' "Published releases require WISENT_NOTARY_PROFILE."
    false
fi
case "$VERSION_WITHOUT_BUILD" in
    *-*) BUILD_CHANNEL=preview ;;
    *) BUILD_CHANNEL=stable ;;
esac
TAMA_CODESIGN_TIMESTAMP=--timestamp \
TAMA_BUILD_CHANNEL="$BUILD_CHANNEL" \
TAMA_INSTALL_AFTER_BUILD=no \
TAMA_RELEASE_VERSION="$PRODUCT_VERSION" \
sh "$SCRIPT_DIR/build-app.sh"
TAMA_BUILD_MANIFEST="$DESKTOP_ROOT/.build/Tama.app/Contents/Resources/tama-build.json" \
python3 - <<'PY'
import json
import os
from pathlib import Path

manifest = json.loads(Path(os.environ["TAMA_BUILD_MANIFEST"]).read_text())
if manifest.get("sourceDirty"):
    raise SystemExit("Desktop build provenance reports dirty source")
hook_release = manifest.get("hookRelease") or {}
if hook_release.get("sourceDirty"):
    raise SystemExit("Hook release provenance reports dirty source")
dependencies = manifest.get("dependencies") or []
if not dependencies:
    raise SystemExit("Build provenance contains no resolved dependencies")
for dependency in dependencies:
    if not (dependency.get("state") or {}).get("revision"):
        raise SystemExit("A resolved dependency is missing its exact revision")
PY

APP="$DESKTOP_ROOT/.build/Tama.app"
APP_PRODUCT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :TamaProductVersion' "$APP/Contents/Info.plist")
APP_BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
FILTER_INFO="$APP/Contents/Library/SystemExtensions/ai.wisent.tama.network-filter.systemextension/Contents/Info.plist"
FILTER_PRODUCT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :TamaProductVersion' "$FILTER_INFO")
FILTER_BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FILTER_INFO")
if [ "$APP_PRODUCT_VERSION" != "$PRODUCT_VERSION" ] \
    || [ "$FILTER_PRODUCT_VERSION" != "$PRODUCT_VERSION" ] \
    || [ "$APP_BUNDLE_VERSION" != "$BUNDLE_SHORT_VERSION" ] \
    || [ "$FILTER_BUNDLE_VERSION" != "$BUNDLE_SHORT_VERSION" ]; then
    printf '%s\n' "Built component product or Apple bundle versions do not match $TAG."
    false
fi
NOTARY_DIR="$DESKTOP_ROOT/.build/notary/$PRODUCT_VERSION"
NOTARY_ZIP="$NOTARY_DIR/Tama-notarization.zip"
if [ -e "$NOTARY_ZIP" ]; then
    printf '%s\n' "Refusing to overwrite an existing notarization submission."
    false
fi
mkdir -p "$NOTARY_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$NOTARY_ZIP"
codesign --verify --strict --deep "$APP"
spctl --assess --type execute "$APP"
ARCH=$(uname -m)
RELEASE_DIR="$DESKTOP_ROOT/.build/releases/$PRODUCT_VERSION"
ARTIFACT_NAME="Tama-$PRODUCT_VERSION-macOS-$ARCH.zip"
ARTIFACT="$RELEASE_DIR/$ARTIFACT_NAME"
DIGEST_FILE="$ARTIFACT.digest"
PROVENANCE_FILE="$ARTIFACT.provenance.json"
QUALIFICATION_FILE="$ARTIFACT.qualification.json"
for output in "$ARTIFACT" "$DIGEST_FILE" "$PROVENANCE_FILE" "$QUALIFICATION_FILE"; do
    if [ -e "$output" ]; then
        printf 'Refusing to overwrite immutable release output: %s\n' "$output"
        false
    fi
done
mkdir -p "$RELEASE_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARTIFACT"
DIGEST=$(python3 "$SCRIPT_DIR/seal_hook_release.py" --digest-file "$ARTIFACT")
printf '%s  %s\n' "$DIGEST" "$ARTIFACT_NAME" > "$DIGEST_FILE"
TAMA_ARTIFACT="$ARTIFACT" \
TAMA_ARTIFACT_DIGEST="$DIGEST" \
TAMA_ARTIFACT_NAME="$ARTIFACT_NAME" \
TAMA_PROVENANCE_SOURCE="$APP/Contents/Resources/tama-build.json" \
python3 - "$PROVENANCE_FILE" <<'PY'
import json
import os
from pathlib import Path
import sys

artifact = Path(os.environ["TAMA_ARTIFACT"])
build = json.loads(Path(os.environ["TAMA_PROVENANCE_SOURCE"]).read_text())
provenance = {
    **build,
    "artifactByteSize": artifact.stat().st_size,
    "artifactDigest": os.environ["TAMA_ARTIFACT_DIGEST"],
    "artifactName": os.environ["TAMA_ARTIFACT_NAME"],
    "canonicalExamples": {
        "path": "examples",
        "sourceRevision": build["sourceRevision"],
        "url": (
            "https://github.com/wisent-ai/tama-desktop/tree/"
            f"v{build['productVersion']}/examples"
        ),
    },
    "schema": "ai.wisent.tama.release-provenance",
}
target = next(argument for argument in sys.argv if argument != "-")
Path(target).write_text(
    json.dumps(provenance, indent=len("  "), sort_keys=True) + "\n"
)
PY
printf 'Packaged immutable release candidate: %s\n' "$ARTIFACT"
printf 'Digest: %s\n' "$DIGEST"
