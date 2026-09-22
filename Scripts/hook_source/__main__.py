#!/usr/bin/env python3
"""Pin and verify the committed Tama source packaged by the desktop release."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import subprocess
import tarfile
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
PIN = PROJECT / "Release/tama-revision"
VENDOR = PROJECT / "Release/vendor/tama"
SOURCE = PROJECT.parent / "tama"


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(io.DEFAULT_BUFFER_SIZE), b""):
            result.update(chunk)
    return result.hexdigest()


def read_pin() -> dict[str, str]:
    revision = PIN.read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"{PIN}: revision must be a full Git commit")
    checksum = archive_path(revision).with_name("source.sha256")
    sha256 = checksum.read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise ValueError(f"{checksum}: expected a full archive digest")
    return {"revision": revision, "sha256": sha256}


def archive_path(revision: str) -> Path:
    return VENDOR / revision / "source.tar.gz"


def verify_archive(archive: Path, pin: dict[str, str]) -> Path:
    actual = digest(archive)
    if actual != pin["sha256"]:
        raise ValueError(f"{archive}: expected sha256 {pin['sha256']}, observed {actual}")
    with tarfile.open(archive, "r:gz") as source:
        observed = source.pax_headers.get("comment")
        if observed != pin["revision"]:
            raise ValueError(f"{archive}: expected Git commit {pin['revision']}, observed {observed!r}")
    return archive


def verify() -> Path:
    pin = read_pin()
    return verify_archive(archive_path(pin["revision"]), pin)


def pin_source(revision: str) -> dict[str, str]:
    result = subprocess.run(
        ["git", "-C", str(SOURCE), "rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"],
        text=True, capture_output=True, check=True,
    )
    resolved = result.stdout.strip()
    if revision != resolved:
        raise ValueError(f"supply the full committed source revision, not {revision!r}; resolved {resolved}")
    previous = read_pin() if PIN.exists() else None
    staging = PROJECT / ".build/source-pin"
    staging.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pin-", dir=staging) as directory:
        archive = Path(directory) / "source.tar.gz"
        subprocess.run(
            ["git", "-C", str(SOURCE), "archive", "--format=tar.gz", "--prefix=tama/",
             f"--output={archive}", resolved],
            text=True, capture_output=True, check=True,
        )
        value = {"revision": resolved, "sha256": digest(archive)}
        verify_archive(archive, value)
        destination = archive_path(resolved)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if digest(destination) != value["sha256"]:
                raise ValueError(f"refusing to replace different bytes at immutable source {destination}")
        else:
            archive.replace(destination)
        checksum = Path(directory) / "source.sha256"
        checksum.write_text(value["sha256"] + "\n")
        checksum.replace(destination.with_name("source.sha256"))
        pending = Path(directory) / PIN.name
        pending.write_text(resolved + "\n")
        pending.replace(PIN)
    if previous and previous["revision"] != resolved:
        superseded = archive_path(previous["revision"])
        superseded.unlink(missing_ok=True)
        superseded.with_name("source.sha256").unlink(missing_ok=True)
        if superseded.parent.is_dir() and not any(superseded.parent.iterdir()):
            superseded.parent.rmdir()
    return value


def unpack(destination: Path) -> Path:
    pin = read_pin()
    archive = verify_archive(archive_path(pin["revision"]), pin)
    root = destination.resolve() / "tama"
    if root.exists():
        raise ValueError(f"refusing to overwrite an existing source directory: {root}")
    with tarfile.open(archive, "r:gz") as source:
        for member in source.getmembers():
            if member.name != "tama" and not member.name.startswith("tama/"):
                raise ValueError(f"archive member is outside the Tama source: {member.name}")
            if member.name == "tama/.tama-source-archive.json":
                raise ValueError("the committed source must not supply its own archive identity")
        destination.mkdir(parents=True, exist_ok=True)
        source.extractall(destination, filter="data")
    origin = {"schema": 1, "archive": str(archive.resolve()), **pin}
    (root / ".tama-source-archive.json").write_text(json.dumps(origin, sort_keys=True) + "\n")
    return root


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    pin = commands.add_parser("pin", help="Archive one committed sibling Tama revision and update its pin")
    pin.add_argument("--revision", required=True)
    commands.add_parser("verify", help="Verify the pinned bytes and embedded Git commit; print the archive path")
    extract = commands.add_parser("unpack", help="Verify and unpack immutable source with its archive identity")
    extract.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "pin":
            print(json.dumps(pin_source(args.revision)))
        elif args.command == "unpack":
            print(unpack(args.destination))
        else:
            print(verify())
    except (OSError, ValueError, tarfile.TarError, subprocess.CalledProcessError) as error:
        if isinstance(error, subprocess.CalledProcessError):
            detail = f"{error.cmd!r} exited {error.returncode}: {error.stderr.strip()}"
        else:
            detail = str(error)
        parser.exit(status=1, message=f"Tama source pin refused: {detail}\n")


if __name__ == "__main__":
    main()
