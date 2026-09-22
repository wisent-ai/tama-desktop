#!/usr/bin/env python3
"""Read and verify the source identity used by native packaging and sealing."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tarfile


SOURCE_INPUTS = (
    "package.json", "shared-hooks", "claude-hooks", "codex-hooks", "repo-githooks", "rust",
)
PRUNED_GENERATORS = {
    "shared-hooks/generate-configs.mjs",
    "shared-hooks/providers.json",
    "shared-hooks/run-one-session-hook.js",
}


def source_git(source_root: Path, *arguments: str) -> str:
    environment = {
        key: value for key, value in os.environ.items()
        if key not in {"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"}
    }
    result = subprocess.run(
        ["git", "-C", str(source_root), *arguments],
        env=environment, capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            f"Reading hook source identity at {source_root}: "
            f"git {' '.join(arguments)} exited {result.returncode}: {detail}"
        )
    return result.stdout


def stream_digest(stream) -> str:
    digest = hashlib.sha256()
    for block in iter(lambda: stream.read(io.DEFAULT_BUFFER_SIZE), b""):
        digest.update(block)
    return digest.hexdigest()


def file_digest(path: Path) -> str:
    with path.open("rb") as source:
        return stream_digest(source)


def archived_inputs(source_root: Path) -> tuple[str, dict]:
    marker = source_root / ".tama-source-archive.json"
    origin = json.loads(marker.read_text())
    if (not isinstance(origin, dict) or origin.get("schema") != 1
            or not all(isinstance(origin.get(key), str) for key in ("archive", "revision", "sha256"))
            or not re.fullmatch(r"[0-9a-f]{40}", origin["revision"])
            or not re.fullmatch(r"[0-9a-f]{64}", origin["sha256"])):
        raise RuntimeError(f"Invalid immutable source identity: {marker}")
    archive_path = Path(origin["archive"])
    if file_digest(archive_path) != origin["sha256"]:
        raise RuntimeError(f"Immutable source archive digest changed: {archive_path}")
    entries = {}
    with tarfile.open(archive_path, "r:gz") as archive:
        if archive.pax_headers.get("comment") != origin["revision"]:
            raise RuntimeError(f"Immutable source archive has a different Git revision: {archive_path}")
        for member in archive.getmembers():
            relative = member.name.removeprefix("tama/")
            if member.isdir() or relative.split("/", 1)[0] not in SOURCE_INPUTS:
                continue
            filtered = tarfile.data_filter(member, str(source_root.parent))
            if not member.isfile() and not member.issym():
                raise RuntimeError(f"Unsupported immutable source input: {member.name}")
            with archive.extractfile(member) as stream:
                entries[relative] = {
                    "path": relative, "mode": filtered.mode,
                    "target": member.linkname if member.issym() else None,
                    "digest": stream_digest(stream),
                }
    if not entries:
        raise RuntimeError(f"Immutable archive contains no Tama source inputs: {archive_path}")
    return origin["revision"], entries


def unpacked_paths(source_root: Path) -> set[str]:
    paths = set()
    for name in SOURCE_INPUTS:
        root = source_root / name
        if root.is_file() or root.is_symlink():
            paths.add(name)
            continue
        for directory, children, files in os.walk(root):
            children[:] = [child for child in children
                           if child != "__pycache__" and Path(directory, child) != source_root / "rust/target"]
            paths.update(str(Path(directory, child).relative_to(source_root)) for child in files
                         if not child.endswith(".pyc"))
            for child in list(children):
                path = Path(directory, child)
                if path.is_symlink():
                    paths.add(str(path.relative_to(source_root)))
                    children.remove(child)
    return paths


def source_identity(source_root: Path, release_root: Path | None = None) -> dict:
    archived = None
    if (source_root / ".tama-source-archive.json").exists():
        if (source_root / ".git").exists():
            raise RuntimeError(f"Source cannot be both a checkout and an immutable archive: {source_root}")
        revision, archived = archived_inputs(source_root)
        dirty = False
        paths = set(archived) | unpacked_paths(source_root)
    else:
        checkout = Path(source_git(source_root, "rev-parse", "--show-toplevel").strip()).resolve()
        if checkout != source_root.resolve():
            raise RuntimeError(f"Hook source root {source_root} is not the Git checkout root {checkout}")
        revision = source_git(source_root, "rev-parse", "--verify", "HEAD").strip()
        dirty = bool(source_git(source_root, "status", "--porcelain", "--untracked-files=normal"))
        paths = set(source_git(
            source_root, "ls-files", "--cached", "--others", "--exclude-standard", "-z",
            "--", *SOURCE_INPUTS,
        ).split("\0")) - {""}
    fingerprint = hashlib.sha256()
    for relative in sorted(paths):
        path = source_root / relative
        if archived is not None and relative not in archived:
            raise RuntimeError(f"Additional source input is not in the pinned archive: {path}")
        entry = {"path": relative, "mode": None, "target": None, "digest": None}
        if path.exists() or path.is_symlink():
            entry["mode"] = stat.S_IMODE(path.lstat().st_mode)
            if path.is_symlink():
                entry["target"] = os.readlink(path)
            if not path.is_file():
                raise RuntimeError(f"Hook source input is not a readable file: {path}")
            entry["digest"] = file_digest(path)
            if release_root is not None and not relative.startswith("rust/"):
                staged = release_root / relative
                pruned = relative in PRUNED_GENERATORS and not staged.exists()
                if not pruned and (not staged.is_file() or file_digest(staged) != entry["digest"]):
                    raise RuntimeError(
                        f"Staged hook source differs from {path}: {staged}; restage the release"
                    )
        elif release_root is not None and not relative.startswith("rust/"):
            staged = release_root / relative
            if staged.exists():
                raise RuntimeError(f"Deleted hook source remains staged: {staged}; restage the release")
        if archived is not None:
            expected = archived.get(relative)
            if expected is not None and expected["target"] is not None:
                expected = {**expected, "mode": entry["mode"]}
            if entry != expected:
                raise RuntimeError(f"Immutable source input differs from its pinned archive: {path}")
        fingerprint.update(json.dumps(entry, sort_keys=True).encode())
        fingerprint.update(b"\n")
    return {"revision": revision, "dirty": dirty, "fingerprint": fingerprint.hexdigest()}


def verify_source_identity(source_root: Path, expected: dict) -> None:
    observed = source_identity(source_root)
    if observed != expected:
        raise RuntimeError(
            f"Hook source changed after staging at {source_root}: "
            f"expected {json.dumps(expected, sort_keys=True)}, "
            f"observed {json.dumps(observed, sort_keys=True)}; restage the release"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--shell", action="store_true", help="Print the revision and dirty flag")
    args = parser.parse_args()
    try:
        identity = source_identity(args.source_root.resolve())
    except (OSError, RuntimeError, ValueError, tarfile.TarError) as error:
        parser.exit(status=1, message=f"Tama source identity refused: {error}\n")
    if args.shell:
        print(identity["revision"], str(identity["dirty"]).lower())
    else:
        print(json.dumps(identity, sort_keys=True))


if __name__ == "__main__":
    main()
