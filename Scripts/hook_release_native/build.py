"""Cargo artifact discovery used by the hook release packager."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess


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
