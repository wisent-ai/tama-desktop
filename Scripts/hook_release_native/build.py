"""Cargo artifact discovery used by the hook release packager."""

from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import stat


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


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(io.DEFAULT_BUFFER_SIZE), b""):
            digest.update(block)
    return digest.hexdigest()


def source_identity(source_root: Path, release_root: Path | None = None) -> dict:
    checkout = Path(source_git(source_root, "rev-parse", "--show-toplevel").strip()).resolve()
    if checkout != source_root.resolve():
        raise RuntimeError(f"Hook source root {source_root} is not the Git checkout root {checkout}")
    revision = source_git(source_root, "rev-parse", "--verify", "HEAD").strip()
    dirty = bool(source_git(source_root, "status", "--porcelain", "--untracked-files=normal"))
    paths = source_git(
        source_root, "ls-files", "--cached", "--others", "--exclude-standard", "-z",
        "--", *SOURCE_INPUTS,
    )
    fingerprint = hashlib.sha256()
    for relative in sorted(set(paths.split("\0")) - {""}):
        path = source_root / relative
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


def cargo_metadata(cargo: Path, source_root: Path) -> dict:
    manifest = source_root / "rust/Cargo.toml"
    result = subprocess.run(
        [
            str(cargo),
            "metadata",
            "--format-version",
            "1",
            "--no-deps",
            "--manifest-path",
            str(manifest),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        detail = "\n".join(part.strip() for part in (result.stderr, result.stdout) if part.strip())
        raise RuntimeError(f"Cargo metadata exited {result.returncode}: {detail or 'no diagnostic'}")
    try:
        metadata = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("Cargo metadata returned invalid JSON") from error
    if not isinstance(metadata, dict):
        raise RuntimeError("Cargo metadata did not return an object")
    return metadata


def binary_targets(metadata: dict) -> dict[str, dict]:
    targets: dict[str, dict] = {}
    duplicates: set[str] = set()
    for package in metadata.get("packages", []):
        if not isinstance(package, dict):
            continue
        package_name = package.get("name")
        for target in package.get("targets", []):
            if (
                not isinstance(target, dict)
                or not isinstance(target.get("name"), str)
                or "bin" not in target.get("kind", [])
            ):
                continue
            name = target["name"]
            if name in targets:
                duplicates.add(name)
                continue
            targets[name] = {
                "name": name,
                "package": package_name,
                "source": target.get("src_path"),
            }
    if duplicates:
        raise RuntimeError(
            "Cargo workspace has ambiguous binary targets: "
            + ", ".join(sorted(duplicates))
        )
    return targets


def build_binaries(
    cargo: Path,
    metadata: dict,
    selected: dict[str, dict],
) -> dict[str, Path]:
    workspace_root = Path(metadata["workspace_root"]).resolve()
    workspace_manifest = workspace_root / "Cargo.toml"
    target_directory = Path(metadata["target_directory"]).resolve()
    by_package: dict[str, list[str]] = {}
    for name, target in selected.items():
        package = target.get("package")
        if not isinstance(package, str):
            raise RuntimeError(f"Cargo target has no package: {name}")
        by_package.setdefault(package, []).append(name)

    artifacts: dict[str, Path] = {}
    for package, names in sorted(by_package.items()):
        command = [
            str(cargo),
            "build",
            "--release",
            "--manifest-path",
            str(workspace_manifest),
            "--package",
            package,
            "--message-format=json-render-diagnostics",
        ]
        for name in sorted(names):
            command.extend(["--bin", name])
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            diagnostics = []
            for line in result.stdout.splitlines():
                if not line.strip():
                    continue
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    diagnostics.append(line)
                    continue
                if isinstance(item, dict) and item.get("reason") == "compiler-message":
                    diagnostics.append(item.get("message", {}).get("rendered", ""))
            detail = "\n".join(
                part.strip() for part in (result.stderr, *diagnostics) if part.strip()
            )
            raise RuntimeError(
                f"Cargo build for {package} exited {result.returncode}: {detail or 'no diagnostic'}"
            )
        for line in result.stdout.splitlines():
            if not line.strip():
                continue
            item = json.loads(line)
            if not isinstance(item, dict) or item.get("reason") != "compiler-artifact":
                continue
            target = item.get("target", {})
            name = target.get("name") if isinstance(target, dict) else None
            executable = item.get("executable")
            if name not in selected or not isinstance(executable, str):
                continue
            artifact = Path(executable).resolve()
            try:
                artifact.relative_to(target_directory)
            except ValueError as error:
                raise RuntimeError(
                    f"Cargo emitted {name} outside its metadata target directory"
                ) from error
            artifacts[name] = artifact

    missing = sorted(set(selected) - set(artifacts))
    if missing:
        raise RuntimeError(
            "Cargo did not emit requested binaries: " + ", ".join(missing)
        )
    for name, artifact in artifacts.items():
        if not artifact.is_file():
            raise RuntimeError(f"Cargo binary is missing: {name}: {artifact}")
    return artifacts


def manifest_entry(target: dict, workspace_root: Path) -> dict:
    source = Path(target["source"]).resolve()
    try:
        source_name = source.relative_to(workspace_root).as_posix()
    except ValueError:
        source_name = str(source)
    return {
        "name": target["name"],
        "package": target["package"],
        "source": source_name,
    }
