"""The small steps publish-release.sh runs in Python, one subcommand each.

`python3 publication.py <step>` reads the TAMA_* environment the script sets
for that step and prints what the script reads back, or exits non-zero with
the reason the publication stops.
"""

import json
import os
import sys
from pathlib import Path
from urllib.parse import quote


def render_notes():
    """Write the release notes for this version from Release/release-notes.json."""
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


def create_request():
    """Write the draft release request GitHub is sent."""
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


def upload_url():
    """Print the upload URL of one asset of the draft release."""
    release_id = os.environ["TAMA_RELEASE_ID"]
    if not release_id or not release_id.isdecimal():
        raise SystemExit("GitHub returned an invalid release ID")
    asset_name = quote(os.environ["TAMA_RELEASE_ASSET_NAME"], safe="")
    print(
        "https://uploads.github.com/repos/wisent-ai/tama-desktop/"
        f"releases/{quote(release_id, safe='')}/assets?name={asset_name}"
    )


def asset_names():
    """Print the names of the assets GitHub holds for the release."""
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


def asset_id():
    """Print the ID of the one uploaded asset with the expected name and size."""
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


def check_metadata():
    """Refuse release metadata that differs from the canonical candidate."""
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


STEPS = {
    "render-notes": render_notes,
    "create-request": create_request,
    "upload-url": upload_url,
    "asset-names": asset_names,
    "asset-id": asset_id,
    "check-metadata": check_metadata,
}

if __name__ == "__main__":
    if len(sys.argv) != len(("program", "step")) or sys.argv[1] not in STEPS:
        raise SystemExit(f"usage: publication.py <{"|".join(STEPS)}>")
    STEPS[sys.argv[1]]()
