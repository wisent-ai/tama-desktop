#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
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
    *) printf '%s\n' "Publication requires the exact signed v<SemVer> release tag at HEAD."; false ;;
esac
SEMVER_CORE='(0|[1-9][0-9]*)'
SEMVER_PRERELEASE_IDENTIFIER='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
SEMVER_PATTERN="^${SEMVER_CORE}\.${SEMVER_CORE}\.${SEMVER_CORE}(-${SEMVER_PRERELEASE_IDENTIFIER}(\.${SEMVER_PRERELEASE_IDENTIFIER})*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"
if ! printf '%s\n' "$PRODUCT_VERSION" | LC_ALL=C grep -Eq "$SEMVER_PATTERN"; then
    printf '%s\n' "Release tag is not valid Semantic Versioning: $TAG"
    false
fi
if [ -n "$(git -C "$DESKTOP_ROOT" status --porcelain --untracked-files=normal)" ]; then
    printf '%s\n' "Publication checkout must be clean."
    false
fi
git -C "$DESKTOP_ROOT" verify-tag "$TAG"
if [ "$(git -C "$DESKTOP_ROOT" rev-parse "$TAG^{}")" != "$(git -C "$DESKTOP_ROOT" rev-parse HEAD)" ]; then
    printf '%s\n' "Selected release tag does not resolve to HEAD: $TAG"
    false
fi
RELEASE_DIR="$DESKTOP_ROOT/.build/releases/$PRODUCT_VERSION"
ARTIFACT=
for candidate in "$RELEASE_DIR"/*.zip; do
    [ -f "$candidate" ] || continue
    if [ -n "$ARTIFACT" ]; then
        printf '%s\n' "Release directory contains more than one zip artifact."
        false
    fi
    ARTIFACT=$candidate
done
if [ -z "$ARTIFACT" ]; then
    printf '%s\n' "No packaged artifact exists for $TAG."
    false
fi
DIGEST_FILE="$ARTIFACT.digest"
PROVENANCE_FILE="$ARTIFACT.provenance.json"
QUALIFICATION_FILE="$ARTIFACT.qualification.json"
for required in "$DIGEST_FILE" "$PROVENANCE_FILE" "$QUALIFICATION_FILE"; do
    if [ ! -f "$required" ]; then
        printf 'Missing release sidecar: %s\n' "$required"
        false
    fi
done
read -r EXPECTED_DIGEST EXPECTED_NAME < "$DIGEST_FILE"
ACTUAL_DIGEST=$(python3 "$SCRIPT_DIR/../hook_release/seal_hook_release.py" --digest-file "$ARTIFACT")
if [ "$EXPECTED_DIGEST" != "$ACTUAL_DIGEST" ] || [ "$EXPECTED_NAME" != "$(basename "$ARTIFACT")" ]; then
    printf '%s\n' "Artifact digest sidecar does not match the packaged bytes."
    false
fi
SOURCE_REVISION=$(git -C "$DESKTOP_ROOT" rev-parse HEAD)
TAMA_ACTUAL_DIGEST="$ACTUAL_DIGEST" \
TAMA_ARTIFACT="$ARTIFACT" \
TAMA_DESKTOP_ROOT="$DESKTOP_ROOT" \
TAMA_PRODUCT_VERSION="$PRODUCT_VERSION" \
TAMA_PROVENANCE_FILE="$PROVENANCE_FILE" \
TAMA_QUALIFICATION_FILE="$QUALIFICATION_FILE" \
TAMA_SOURCE_REVISION="$SOURCE_REVISION" \
python3 "$SCRIPT_DIR/validate_artifact.py"
if ! gh api -H "X-GitHub-Api-Version: 2026-03-10" \
    "repos/wisent-ai/tama-desktop/immutable-releases" >/dev/null
then
    printf '%s\n' "GitHub release immutability must be enabled and visible to the publication identity."
    false
fi
if gh release view "$TAG" --repo wisent-ai/tama-desktop >/dev/null; then
    printf '%s\n' "Refusing to replace existing immutable GitHub release $TAG."
    false
fi
VALIDATION_DIR=$(mktemp -d "$RELEASE_DIR/publish-validation.XXXXXX")
DRAFT_CREATED=no
CREATED_RELEASE_ID=
cleanup_publication() {
    status=$?
    trap - EXIT
    rm -rf -- "$VALIDATION_DIR"
    if [ -n "${REMOTE_ASSET_DIR:-}" ]; then
        rm -rf -- "$REMOTE_ASSET_DIR"
    fi
    if [ -n "${PUBLISHED_ASSET_DIR:-}" ]; then
        rm -rf -- "$PUBLISHED_ASSET_DIR"
    fi
    if [ "$DRAFT_CREATED" = yes ]; then
        release_is_draft=$(gh api \
            -H "X-GitHub-Api-Version: 2026-03-10" \
            "repos/wisent-ai/tama-desktop/releases/$CREATED_RELEASE_ID" \
            --jq .draft || printf '%s' unknown)
        case "$release_is_draft" in
            true)
                printf '%s\n' "Incomplete draft release $TAG has GitHub ID $CREATED_RELEASE_ID."
                printf '%s\n' "Automatic cleanup cannot atomically guarantee draft state; inspect and delete only that incomplete draft before retrying."
                ;;
            false)
                printf '%s\n' "Release $TAG with GitHub ID $CREATED_RELEASE_ID is already public; preserving it."
                ;;
            *)
                printf '%s\n' "Could not inspect GitHub release ID $CREATED_RELEASE_ID; inspect the release before retrying."
                false
                ;;
        esac
    fi
    exit "$status"
}
trap cleanup_publication EXIT
ditto -x -k "$ARTIFACT" "$VALIDATION_DIR"
VALIDATION_APP="$VALIDATION_DIR/Tama.app"
if [ ! -d "$VALIDATION_APP" ]; then
    printf '%s\n' "Release artifact does not contain the expected Tama.app bundle."
    false
fi
codesign --verify --strict --deep "$VALIDATION_APP"
xcrun stapler validate "$VALIDATION_APP"
spctl --assess --type execute "$VALIDATION_APP"
NOTES_FILE="$RELEASE_DIR/release-notes.md"
TAMA_RELEASE_NOTES_SOURCE="$DESKTOP_ROOT/Release/release-notes.json" \
TAMA_QUALIFICATION_NAME="$(basename "$QUALIFICATION_FILE")" \
TAMA_RELEASE_NOTES="$NOTES_FILE" \
TAMA_RELEASE_VERSION="$PRODUCT_VERSION" \
TAMA_RELEASE_TAG="$TAG" \
python3 "$SCRIPT_DIR/publication.py" render-notes
VERSION_WITHOUT_BUILD=${PRODUCT_VERSION%%+*}
case "$VERSION_WITHOUT_BUILD" in
    *-*) EXPECTED_PRERELEASE=true; RELEASE_MAKE_LATEST=false ;;
    *) EXPECTED_PRERELEASE=false; RELEASE_MAKE_LATEST=true ;;
esac
LOCAL_TAG_OBJECT=$(git -C "$DESKTOP_ROOT" rev-parse "$TAG^{tag}")
REMOTE_TAG_OBJECT=$(gh api \
    "repos/wisent-ai/tama-desktop/git/ref/tags/$TAG" \
    --jq .object.sha)
if [ "$REMOTE_TAG_OBJECT" != "$LOCAL_TAG_OBJECT" ]; then
    printf '%s\n' "Remote release tag $TAG is not the locally verified signed tag object."
    false
fi
CREATE_REQUEST_FILE="$VALIDATION_DIR/release-create-request.json"
TAMA_CREATE_REQUEST_FILE="$CREATE_REQUEST_FILE" \
TAMA_EXPECTED_PRERELEASE="$EXPECTED_PRERELEASE" \
TAMA_RELEASE_NOTES="$NOTES_FILE" \
TAMA_RELEASE_TAG="$TAG" \
TAMA_RELEASE_TITLE="Tama $PRODUCT_VERSION" \
python3 "$SCRIPT_DIR/publication.py" create-request
if CREATED_RELEASE_ID=$(gh api \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    --method POST \
    "repos/wisent-ai/tama-desktop/releases" \
    --input "$CREATE_REQUEST_FILE" \
    --jq .id)
then
    DRAFT_CREATED=yes
else
    printf '%s\n' "Draft creation for $TAG was unsuccessful or uncertain."
    printf '%s\n' "Publication will not delete a draft without the release ID returned to this invocation; inspect GitHub and remove only the incomplete matching draft before retrying."
    false
fi
for UPLOAD_ASSET in \
    "$ARTIFACT" \
    "$DIGEST_FILE" \
    "$PROVENANCE_FILE" \
    "$QUALIFICATION_FILE"
do
    UPLOAD_ASSET_URL=$(
        TAMA_RELEASE_ASSET_NAME="$(basename "$UPLOAD_ASSET")" \
        TAMA_RELEASE_ID="$CREATED_RELEASE_ID" \
        python3 "$SCRIPT_DIR/publication.py" upload-url
    )
    gh api \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/octet-stream" \
        -H "X-GitHub-Api-Version: 2026-03-10" \
        --method POST \
        "$UPLOAD_ASSET_URL" \
        --input "$UPLOAD_ASSET" \
        >/dev/null
done
REMOTE_ASSET_DIR=$(mktemp -d "$RELEASE_DIR/remote-assets.XXXXXX")
EXPECTED_ASSET_NAMES=$(
    printf '%s\n' \
        "$(basename "$ARTIFACT")" \
        "$(basename "$DIGEST_FILE")" \
        "$(basename "$PROVENANCE_FILE")" \
        "$(basename "$QUALIFICATION_FILE")" |
        LC_ALL=C sort
)
verify_remote_assets() {
    RELEASE_ASSET_METADATA_FILE="$ASSET_VERIFICATION_DIR/release-assets.json"
    gh api \
        -H "X-GitHub-Api-Version: 2026-03-10" \
        --paginate \
        --slurp \
        "repos/wisent-ai/tama-desktop/releases/$CREATED_RELEASE_ID/assets" \
        > "$RELEASE_ASSET_METADATA_FILE"
    REMOTE_ASSET_NAMES=$(
        TAMA_RELEASE_ASSET_METADATA_FILE="$RELEASE_ASSET_METADATA_FILE" \
        python3 "$SCRIPT_DIR/publication.py" asset-names
    )
    if [ "$REMOTE_ASSET_NAMES" != "$EXPECTED_ASSET_NAMES" ]; then
        printf '%s\n' "Release asset names do not exactly match the canonical release set."
        false
    fi
    for LOCAL_ASSET in \
        "$ARTIFACT" \
        "$DIGEST_FILE" \
        "$PROVENANCE_FILE" \
        "$QUALIFICATION_FILE"
    do
        REMOTE_ASSET_NAME=$(basename "$LOCAL_ASSET")
        REMOTE_ASSET_ID=$(
            TAMA_EXPECTED_ASSET_NAME="$REMOTE_ASSET_NAME" \
            TAMA_LOCAL_ASSET="$LOCAL_ASSET" \
            TAMA_RELEASE_ASSET_METADATA_FILE="$RELEASE_ASSET_METADATA_FILE" \
            python3 "$SCRIPT_DIR/publication.py" asset-id
        )
        REMOTE_ASSET="$ASSET_VERIFICATION_DIR/$REMOTE_ASSET_NAME"
        gh api \
            -H "X-GitHub-Api-Version: 2026-03-10" \
            -H "Accept: application/octet-stream" \
            "repos/wisent-ai/tama-desktop/releases/assets/$REMOTE_ASSET_ID" \
            > "$REMOTE_ASSET"
        if ! cmp -s "$LOCAL_ASSET" "$REMOTE_ASSET"; then
            printf '%s\n' "Release asset $REMOTE_ASSET_NAME differs from the qualified local bytes."
            false
        fi
    done
}
ASSET_VERIFICATION_DIR="$REMOTE_ASSET_DIR"
verify_remote_assets
REMOTE_TAG_OBJECT=$(gh api \
    "repos/wisent-ai/tama-desktop/git/ref/tags/$TAG" \
    --jq .object.sha)
if [ "$REMOTE_TAG_OBJECT" != "$LOCAL_TAG_OBJECT" ]; then
    printf '%s\n' "Remote release tag $TAG changed during draft upload."
    false
fi
RELEASE_METADATA_FILE="$REMOTE_ASSET_DIR/release-metadata.json"
validate_release_metadata() {
    gh api \
        -H "X-GitHub-Api-Version: 2026-03-10" \
        "repos/wisent-ai/tama-desktop/releases/$CREATED_RELEASE_ID" \
        > "$RELEASE_METADATA_FILE"
    TAMA_EXPECTED_DRAFT_STATE="$EXPECTED_DRAFT_STATE" \
    TAMA_EXPECTED_PRERELEASE="$EXPECTED_PRERELEASE" \
    TAMA_RELEASE_ID="$CREATED_RELEASE_ID" \
    TAMA_RELEASE_METADATA_FILE="$RELEASE_METADATA_FILE" \
    TAMA_RELEASE_NOTES="$NOTES_FILE" \
    TAMA_RELEASE_TAG="$TAG" \
    TAMA_RELEASE_TITLE="Tama $PRODUCT_VERSION" \
    python3 "$SCRIPT_DIR/publication.py" check-metadata
}
EXPECTED_DRAFT_STATE=true
validate_release_metadata
if ! gh api -H "X-GitHub-Api-Version: 2026-03-10" \
    "repos/wisent-ai/tama-desktop/immutable-releases" >/dev/null
then
    printf '%s\n' "GitHub release immutability was disabled before publication."
    false
fi
gh api \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    --method PATCH \
    "repos/wisent-ai/tama-desktop/releases/$CREATED_RELEASE_ID" \
    -F draft=false \
    -f make_latest="$RELEASE_MAKE_LATEST" \
    >/dev/null
PUBLISHED_IMMUTABLE=$(gh api \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    "repos/wisent-ai/tama-desktop/releases/$CREATED_RELEASE_ID" \
    --jq .immutable)
if [ "$PUBLISHED_IMMUTABLE" != true ]; then
    printf '%s\n' "Published release $TAG was not confirmed immutable; inspect the public release immediately."
    false
fi
EXPECTED_DRAFT_STATE=false
validate_release_metadata
PUBLISHED_ASSET_DIR=$(mktemp -d "$RELEASE_DIR/published-assets.XXXXXX")
ASSET_VERIFICATION_DIR="$PUBLISHED_ASSET_DIR"
verify_remote_assets
DRAFT_CREATED=no
printf 'Published immutable release %s with digest %s\n' "$TAG" "$ACTUAL_DIGEST"
