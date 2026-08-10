#!/usr/bin/env python3
import hashlib
import json
import os
import pathlib
import tarfile
import tempfile
import urllib.request


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Stado delivery did not provide {name}")
    return value


def extract_member(bundle: tarfile.TarFile, basename: str, destination: pathlib.Path) -> None:
    member = next(
        (item for item in bundle.getmembers() if item.isfile() and pathlib.PurePosixPath(item.name).name == basename),
        None,
    )
    if member is None:
        raise RuntimeError(f"canonical Stado archive has no {basename}")
    payload = bundle.extractfile(member)
    if payload is None:
        raise RuntimeError(f"canonical Stado archive member {basename} is unreadable")
    destination.write_bytes(payload.read())


product = required("WISENT_PRODUCT")
display_name = {"probierz-desktop": "Probierz", "tama-desktop": "Tama"}[product]
version = required("WISENT_VERSION")
archive = pathlib.Path(required("WISENT_RELEASE_ARCHIVE"))
expected_sha = required("WISENT_RELEASE_SHA256")
if hashlib.sha256(archive.read_bytes()).hexdigest() != expected_sha:
    raise RuntimeError("canonical Stado archive digest mismatch")

with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    update_zip = root / f"{display_name}.zip"
    appcast = root / "appcast.xml"
    signature = root / f"{display_name}.zip.sparkle-signature"
    with tarfile.open(archive, "r:gz") as bundle:
        extract_member(bundle, update_zip.name, update_zip)
        extract_member(bundle, appcast.name, appcast)
        extract_member(bundle, signature.name, signature)
    upload_base = required("WISENT_SPARKLE_UPLOAD_BASE_URL").rstrip("/")
    token = required("WISENT_SPARKLE_TOKEN")
    archive_name = f"{display_name}-{version}.zip"
    archive_digest = hashlib.sha256(update_zip.read_bytes()).hexdigest()
    uploads = [
        (update_zip, f"{upload_base}/{product}/{archive_name}", "application/zip"),
        (signature, f"{upload_base}/{product}/{archive_name}.sparkle-signature", "text/plain"),
        (appcast, f"{upload_base}/{product}/appcast.xml", "application/xml"),
    ]
    for source, url, content_type in uploads:
        request = urllib.request.Request(
            url,
            data=source.read_bytes(),
            method="PUT",
            headers={"Authorization": f"Bearer {token}", "Content-Type": content_type},
        )
        with urllib.request.urlopen(request) as response:
            if not 200 <= response.status < 300:
                raise RuntimeError(f"Sparkle upload returned HTTP {response.status}")

public_base = f"https://updates.wisent.ai/{product}"
receipt = {
    "schema_version": 1,
    "channel": "sparkle-appcast",
    "product": product,
    "version": version,
    "platform": required("WISENT_PLATFORM"),
    "release_uri": required("WISENT_RELEASE_URI"),
    "release_sha256": expected_sha,
    "release_manifest_uri": required("WISENT_RELEASE_MANIFEST_URI"),
    "release_manifest_sha256": required("WISENT_RELEASE_MANIFEST_SHA256"),
    "archive_sha256": archive_digest,
    "archive_url": f"{public_base}/{archive_name}",
    "appcast_url": f"{public_base}/appcast.xml",
}
output = pathlib.Path(required("WISENT_OUTPUT_DIR"))
output.mkdir(parents=True, exist_ok=True)
(output / "sparkle-appcast-receipt.json").write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n")
