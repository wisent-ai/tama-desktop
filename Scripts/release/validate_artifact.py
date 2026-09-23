"""Check a packaged Tama release against its sidecars before publication.

Run by publish-release.sh with the TAMA_* environment it sets: the artifact,
its provenance and qualification sidecars, the digest the sealer computed, the
product version and source revision. Exits non-zero with every mismatch listed.
"""
import json
from datetime import datetime
from hashlib import sha256
import os
import plistlib
from pathlib import Path, PurePosixPath
from zipfile import BadZipFile, ZipFile
from validate_qualification import check_qualification

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
check_qualification(
    qualification, product_version, source_revision, artifact, hook_release, architecture, require, parse_timestamp,
)

if errors:
    raise SystemExit("Release publication validation failed:\n- " + "\n- ".join(errors))
