#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DESKTOP_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
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
ACTUAL_DIGEST=$(python3 "$SCRIPT_DIR/seal_hook_release.py" --digest-file "$ARTIFACT")
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
python3 - <<'PY'
import json
from datetime import datetime
from hashlib import sha256
import os
import plistlib
from pathlib import Path, PurePosixPath
from zipfile import BadZipFile, ZipFile

artifact = Path(os.environ["TAMA_ARTIFACT"])
try:
    provenance = json.loads(Path(os.environ["TAMA_PROVENANCE_FILE"]).read_text())
    qualification = json.loads(Path(os.environ["TAMA_QUALIFICATION_FILE"]).read_text())
    with ZipFile(artifact) as archive:
        member_names = [entry.filename for entry in archive.infolist()]
        if len(member_names) != len(set(member_names)):
            raise ValueError("release artifact contains duplicate ZIP member names")
        member_paths = [PurePosixPath(name) for name in member_names]
        if any(path.is_absolute() or ".." in path.parts for path in member_paths):
            raise ValueError("release artifact contains an unsafe ZIP member path")
        allowed_roots = {"Tama.app", "__MACOSX"}
        if any(
            next(iter(path.parts), None) not in allowed_roots
            for path in member_paths
        ):
            raise ValueError("release artifact contains an unexpected top-level ZIP member")
        embedded_build = json.loads(
            archive.read("Tama.app/Contents/Resources/tama-build.json")
        )
        embedded_hook_release = json.loads(
            archive.read("Tama.app/Contents/Resources/hooks-release/release.json")
        )
        embedded_app_info = plistlib.loads(
            archive.read("Tama.app/Contents/Info.plist")
        )
        embedded_filter_info = plistlib.loads(
            archive.read(
                "Tama.app/Contents/Library/SystemExtensions/"
                "ai.wisent.tama.network-filter.systemextension/Contents/Info.plist"
            )
        )
except (BadZipFile, KeyError, OSError, ValueError, json.JSONDecodeError, plistlib.InvalidFileException) as error:
    raise SystemExit(f"Release sidecar or embedded identity is unreadable: {error}")
if not all(
    isinstance(value, dict)
    for value in (
        provenance,
        qualification,
        embedded_build,
        embedded_hook_release,
        embedded_app_info,
        embedded_filter_info,
    )
):
    raise SystemExit("Release sidecars and embedded identities must be JSON objects")

product_version = os.environ["TAMA_PRODUCT_VERSION"]
source_revision = os.environ["TAMA_SOURCE_REVISION"]
version_without_build, ignored_separator, ignored_suffix = product_version.partition("+")
bundle_short_version, ignored_separator, ignored_suffix = version_without_build.partition("-")
errors = []

def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

def parse_timestamp(value: object, label: str):
    if not isinstance(value, str) or not value.strip():
        require(False, f"{label} is not a timestamp")
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        require(False, f"{label} is not an ISO 8601 timestamp")
        return None
    require(parsed.tzinfo is not None, f"{label} has no UTC offset")
    return parsed


require(provenance.get("schema") == "ai.wisent.tama.release-provenance", "unexpected schema")
require(provenance.get("productVersion") == product_version, "product version does not match tag")
require(provenance.get("sourceRevision") == source_revision, "source revision does not match HEAD")
require(provenance.get("sourceDirty") is False, "desktop source is dirty")
require(provenance.get("platform") == "macOS", "unsupported platform")
architecture = provenance.get("architecture")
expected_name = f"Tama-{product_version}-macOS-{architecture}.zip"
require(isinstance(architecture, str) and bool(architecture), "missing architecture")
require(provenance.get("artifactName") == artifact.name == expected_name, "artifact name does not match build identity")
require(provenance.get("artifactDigest") == os.environ["TAMA_ACTUAL_DIGEST"], "provenance digest does not match artifact")
require(provenance.get("artifactByteSize") == artifact.stat().st_size, "provenance byte size does not match artifact")
expected_channel = "preview" if "-" in version_without_build else "stable"
require(provenance.get("channel") == expected_channel, "release channel does not match version")
app_build_number = embedded_app_info.get("CFBundleVersion")
filter_build_number = embedded_filter_info.get("CFBundleVersion")
for component, identity in (
    ("app", embedded_app_info),
    ("network filter", embedded_filter_info),
):
    require(
        identity.get("TamaProductVersion") == product_version,
        f"{component} product identity does not match tag",
    )
    require(
        identity.get("CFBundleShortVersionString") == bundle_short_version,
        f"{component} Apple bundle version does not match SemVer core",
    )
require(
    isinstance(app_build_number, str)
    and bool(app_build_number)
    and app_build_number.isdigit(),
    "app build number is not numeric",
)
require(
    filter_build_number == app_build_number,
    "network filter build number differs from app",
)
require(embedded_build.get("schema") == "ai.wisent.tama.build", "unexpected embedded build schema")
for field in (
    "architecture",
    "builtAt",
    "channel",
    "dependencies",
    "hookRelease",
    "platform",
    "productVersion",
    "sourceDirty",
    "sourceRevision",
):
    require(provenance.get(field) == embedded_build.get(field), f"provenance {field} differs from signed artifact")
require(embedded_build.get("hookRelease") == embedded_hook_release, "embedded hook identity differs from build identity")

hook_release = provenance.get("hookRelease")
require(isinstance(hook_release, dict), "missing hook release identity")
if isinstance(hook_release, dict):
    release_id = hook_release.get("releaseId")
    digest_shape = sha256(b"").hexdigest()
    require(
        isinstance(release_id, str)
        and len(release_id) == len(digest_shape)
        and all(character in "0123456789abcdef" for character in release_id),
        "hook release ID is not a lowercase SHA-256 digest",
    )
    require(hook_release.get("schema") == "ai.wisent.tama.hook-release.v1", "unexpected hook release schema")
    require(bool(hook_release.get("releaseId")), "missing hook release ID")
    require(hook_release.get("sourceDirty") is False, "hook source is dirty")
    require(hook_release.get("sourceRevision") not in (None, "", "unknown"), "missing hook source revision")

dependencies = provenance.get("dependencies")
require(isinstance(dependencies, list) and bool(dependencies), "missing resolved dependencies")
if isinstance(dependencies, list):
    for dependency in dependencies:
        state = dependency.get("state") if isinstance(dependency, dict) else None
        require(
            isinstance(state, dict) and bool(state.get("revision")),
            "resolved dependency is missing its exact revision",
        )

examples = provenance.get("canonicalExamples")
expected_examples_url = (
    "https://github.com/wisent-ai/tama-desktop/tree/"
    f"v{product_version}/examples"
)
require(isinstance(examples, dict), "missing canonical example identity")
if isinstance(examples, dict):
    require(examples.get("path") == "examples", "unexpected canonical example path")
    require(examples.get("sourceRevision") == source_revision, "canonical examples do not match source revision")
    require(examples.get("url") == expected_examples_url, "canonical example URL does not match tag")

qualification_records = qualification.get("records")
expected_hook_release_id = (
    hook_release.get("releaseId") if isinstance(hook_release, dict) else None
)
require(
    qualification.get("schema") == "ai.wisent.tama.release-qualification.vOne",
    "unexpected qualification evidence schema",
)
for field, expected in (
    ("productVersion", product_version),
    ("tag", f"v{product_version}"),
    ("sourceRevision", source_revision),
    ("artifactName", artifact.name),
    ("artifactDigest", os.environ["TAMA_ACTUAL_DIGEST"]),
    ("artifactByteSize", artifact.stat().st_size),
    ("hookReleaseId", expected_hook_release_id),
    ("platform", "macOS"),
    ("architecture", architecture),
):
    require(
        qualification.get(field) == expected,
        f"qualification {field} does not match the candidate",
    )
qualified_at = qualification.get("qualifiedAt")
require(
    isinstance(qualified_at, str) and bool(qualified_at.strip()),
    "qualification evidence has no completion time",
)
qualified_at_timestamp = parse_timestamp(
    qualified_at,
    "qualification completion time",
)
require(
    isinstance(qualification_records, list) and bool(qualification_records),
    "qualification evidence contains no execution records",
)

required_suite_kinds = {
    "swift-contracts",
    "clean-device-e2e",
    "controlled-recovery-provider-release",
}
allowed_suite_kinds = required_suite_kinds | {"canonical-example"}
covered_suite_kinds = set()
record_keys = set()
actual_example_names = []
if isinstance(qualification_records, list):
    for record in qualification_records:
        if not isinstance(record, dict):
            require(False, "qualification execution record is not an object")
            continue
        kind = record.get("kind")
        name = record.get("name")
        if not isinstance(kind, str) or not kind.strip():
            require(False, "qualification execution record has no kind")
            continue
        if not isinstance(name, str) or not name.strip():
            require(False, "qualification execution record has no name")
            continue
        require(kind in allowed_suite_kinds, f"unsupported qualification record kind: {kind}")
        key = (kind, name)
        require(key not in record_keys, f"duplicate qualification execution record: {kind}/{name}")
        record_keys.add(key)
        require(record.get("status") == "passed", f"qualification did not pass: {kind}/{name}")
        require(record.get("redacted") is True, f"qualification result is not marked redacted: {kind}/{name}")
        for field in (
            "startedAt",
            "endedAt",
            "controlledIdentityLabel",
            "preconditionSnapshot",
            "expectedObservableContract",
            "result",
            "failurePathExercised",
            "cleanupResult",
            "operatorApprovalReference",
        ):
            value = record.get(field)
            require(
                isinstance(value, str) and bool(value.strip()),
                f"qualification record {kind}/{name} has no {field}",
            )
        started_at = parse_timestamp(
            record.get("startedAt"),
            f"qualification record {kind}/{name} start time",
        )
        ended_at = parse_timestamp(
            record.get("endedAt"),
            f"qualification record {kind}/{name} end time",
        )
        if started_at is not None and ended_at is not None:
            require(
                started_at <= ended_at,
                f"qualification record {kind}/{name} ends before it starts",
            )
        if ended_at is not None and qualified_at_timestamp is not None:
            require(
                ended_at <= qualified_at_timestamp,
                f"qualification record {kind}/{name} ends after qualification completion",
            )
        for field, expected in (
            ("tag", f"v{product_version}"),
            ("sourceRevision", source_revision),
            ("artifactDigest", os.environ["TAMA_ACTUAL_DIGEST"]),
            ("hookReleaseId", expected_hook_release_id),
            ("platform", "macOS"),
            ("architecture", architecture),
        ):
            require(
                record.get(field) == expected,
                f"qualification record {kind}/{name} has mismatched {field}",
            )
        if kind == "canonical-example":
            actual_example_names.append(name)
        else:
            covered_suite_kinds.add(kind)

desktop_root = Path(os.environ["TAMA_DESKTOP_ROOT"])
expected_example_names = sorted(
    path.relative_to(desktop_root).as_posix()
    for path in (desktop_root / "examples").rglob("*.sh")
    if path.is_file()
)
require(
    sorted(actual_example_names) == expected_example_names,
    "qualification evidence does not cover every canonical example exactly once",
)
require(
    required_suite_kinds.issubset(covered_suite_kinds),
    "qualification evidence does not cover every required suite kind",
)

if errors:
    raise SystemExit("Release publication validation failed:\n- " + "\n- ".join(errors))
PY
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
python3 - <<'PY'
import json
import os
from pathlib import Path
from urllib.parse import quote

version = os.environ["TAMA_RELEASE_VERSION"]
document = json.loads(Path(os.environ["TAMA_RELEASE_NOTES_SOURCE"]).read_text())
qualification_name = os.environ["TAMA_QUALIFICATION_NAME"]
qualification_url = (
    "https://github.com/wisent-ai/tama-desktop/releases/download/"
    f"{quote(os.environ['TAMA_RELEASE_TAG'], safe='')}/"
    f"{quote(qualification_name, safe='')}"
)
qualification_entry = (
    f"- Immutable qualification record: [{qualification_name}]({qualification_url})"
)
matches = [
    release
    for release in document.get("releases", [])
    if release.get("version") == version
]
try:
    release, = matches
except ValueError:
    raise SystemExit(f"Expected exactly one structured release-notes entry for {version}")
required_headings = [
    "Added",
    "Changed",
    "Fixed",
    "Removed or deprecated",
    "Security",
    "Configuration",
    "Data or state migrations",
    "Compatibility requirements",
    "Operator actions",
    "Known limitations",
    "Qualification evidence",
]
sections = release.get("sections") or []
heading_order = [section.get("name") for section in sections]
if heading_order != required_headings:
    raise SystemExit(
        f"Release notes for {version} do not use the required category order"
    )
for section in sections:
    if not section.get("items"):
        raise SystemExit(
            f"Release-notes category {section.get('name', '<unnamed>')} is empty"
        )
rendered = []
for section in sections:
    name = section["name"]
    rendered.extend([f"### {name}", ""])
    if name == "Qualification evidence":
        rendered.extend([qualification_entry, ""])
    rendered.extend(f"- {item}" for item in section["items"])
    rendered.append("")
Path(os.environ["TAMA_RELEASE_NOTES"]).write_text(
    "\n".join(rendered).strip() + "\n"
)
PY
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
python3 - <<'PY'
import json
import os
from pathlib import Path

request = {
    "tag_name": os.environ["TAMA_RELEASE_TAG"],
    "name": os.environ["TAMA_RELEASE_TITLE"],
    "body": Path(os.environ["TAMA_RELEASE_NOTES"]).read_text(),
    "draft": True,
    "prerelease": os.environ["TAMA_EXPECTED_PRERELEASE"] == "true",
}
Path(os.environ["TAMA_CREATE_REQUEST_FILE"]).write_text(
    json.dumps(request, ensure_ascii=False) + "\n"
)
PY
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
        python3 - <<'PY'
import os
from urllib.parse import quote

release_id = os.environ["TAMA_RELEASE_ID"]
if not release_id or not release_id.isdecimal():
    raise SystemExit("GitHub returned an invalid release ID")
asset_name = quote(os.environ["TAMA_RELEASE_ASSET_NAME"], safe="")
print(
    "https://uploads.github.com/repos/wisent-ai/tama-desktop/"
    f"releases/{quote(release_id, safe='')}/assets?name={asset_name}"
)
PY
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
        python3 - <<'PY'
import json
import os
from pathlib import Path

pages = json.loads(
    Path(os.environ["TAMA_RELEASE_ASSET_METADATA_FILE"]).read_text()
)
if not isinstance(pages, list) or any(
    not isinstance(page, list) for page in pages
):
    raise SystemExit("GitHub release asset metadata is not a paginated array")
assets = [asset for page in pages for asset in page]
if any(not isinstance(asset, dict) for asset in assets):
    raise SystemExit("GitHub release asset metadata contains a non-object")
names = [asset.get("name") for asset in assets]
if any(not isinstance(name, str) or not name for name in names):
    raise SystemExit("GitHub release asset metadata contains an invalid name")
print("\n".join(sorted(names)))
PY
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
            python3 - <<'PY'
import json
import os
from pathlib import Path

pages = json.loads(
    Path(os.environ["TAMA_RELEASE_ASSET_METADATA_FILE"]).read_text()
)
assets = [asset for page in pages for asset in page]
expected_name = os.environ["TAMA_EXPECTED_ASSET_NAME"]
matches = [
    asset for asset in assets
    if asset.get("name") == expected_name
]
try:
    asset, = matches
except ValueError:
    raise SystemExit(
        f"Expected exactly one GitHub release asset named {expected_name}"
    )
asset_id = asset.get("id")
if (
    not isinstance(asset_id, int)
    or isinstance(asset_id, bool)
    or asset_id <= int()
):
    raise SystemExit(f"GitHub release asset {expected_name} has no valid ID")
if asset.get("state") != "uploaded":
    raise SystemExit(f"GitHub release asset {expected_name} is not uploaded")
if asset.get("size") != Path(os.environ["TAMA_LOCAL_ASSET"]).stat().st_size:
    raise SystemExit(f"GitHub release asset {expected_name} has the wrong size")
print(asset_id)
PY
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
    python3 - <<'PY'
import json
import os
from pathlib import Path

metadata = json.loads(Path(os.environ["TAMA_RELEASE_METADATA_FILE"]).read_text())
expected = {
    "body": Path(os.environ["TAMA_RELEASE_NOTES"]).read_text(),
    "draft": os.environ["TAMA_EXPECTED_DRAFT_STATE"] == "true",
    "prerelease": os.environ["TAMA_EXPECTED_PRERELEASE"] == "true",
    "name": os.environ["TAMA_RELEASE_TITLE"],
    "tag_name": os.environ["TAMA_RELEASE_TAG"],
}
errors = [
    field
    for field, value in expected.items()
    if metadata.get(field) != value
]
if str(metadata.get("id")) != os.environ["TAMA_RELEASE_ID"]:
    errors.append("id")
if errors:
    raise SystemExit(
        "Release metadata differs from the canonical candidate: "
        + ", ".join(errors)
    )
PY
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
