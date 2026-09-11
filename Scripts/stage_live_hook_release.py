#!/usr/bin/env python3
"""Stage or package a Tama hook release from canonical sources."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

from hook_release_native.build import (
    binary_targets,
    build_binaries,
    cargo_metadata,
    manifest_entry,
    source_identity,
    verify_source_identity,
)

NATIVE_MANIFEST_SCHEMA = "ai.wisent.tama.native-hook-binaries.v1"


def load_object(path: Path) -> dict:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected a JSON object: {path}")
    return value


def command_program(command: str) -> str | None:
    try:
        arguments = shlex.split(command)
    except ValueError as error:
        raise RuntimeError(f"Invalid hook command {command!r}: {error}") from error
    return Path(arguments[0]).name if arguments else None


def registry_command_names(value: object) -> set[str]:
    names: set[str] = set()
    if isinstance(value, dict):
        command = value.get("command")
        if isinstance(command, str):
            program = command_program(command)
            if program:
                names.add(program)
        for nested in value.values():
            names.update(registry_command_names(nested))
    elif isinstance(value, list):
        for nested in value:
            names.update(registry_command_names(nested))
    return names


def rust_declared_command_names(value: object) -> set[str]:
    names: set[str] = set()
    if isinstance(value, dict):
        command = value.get("command")
        source = value.get("source")
        if (
            isinstance(command, str)
            and isinstance(source, str)
            and source.endswith(".rs")
        ):
            program = command_program(command)
            if program:
                names.add(program)
        for nested in value.values():
            names.update(rust_declared_command_names(nested))
    elif isinstance(value, list):
        for nested in value:
            names.update(rust_declared_command_names(nested))
    return names


def package_native_binaries(
    release_root: Path,
    source_root: Path,
    cargo: Path,
    additional_names: list[str],
    codesign_identity: str | None,
    codesign_timestamp: str,
) -> None:
    identity = source_identity(source_root, release_root)
    registry = load_object(release_root / "shared-hooks/registry.json")
    metadata = cargo_metadata(cargo, source_root)
    targets = binary_targets(metadata)
    registered_names = registry_command_names(registry)
    rust_declared_names = rust_declared_command_names(registry)
    hook_names = {name for name in registered_names if name.startswith("tama-")} | rust_declared_names
    missing_rust_targets = sorted(hook_names - set(targets))
    if missing_rust_targets:
        raise RuntimeError(
            "Registry Rust hook commands lack Cargo binary targets: "
            + ", ".join(missing_rust_targets)
        )
    if not hook_names:
        raise RuntimeError("Registry does not reference any Cargo hook binaries")

    additional = sorted(set(additional_names) - hook_names)
    missing_targets = sorted(name for name in additional if name not in targets)
    if missing_targets:
        raise RuntimeError(
            "Cargo metadata is missing requested binaries: "
            + ", ".join(missing_targets)
        )
    selected_names = sorted(hook_names) + additional
    selected = {name: targets[name] for name in selected_names}
    artifacts = build_binaries(cargo, metadata, selected)

    binary_root = release_root / "bin"
    shutil.rmtree(binary_root, ignore_errors=True)
    binary_root.mkdir(parents=True)
    for name in sorted(artifacts):
        destination = binary_root / name
        shutil.copy2(artifacts[name], destination)
        destination.chmod(0o755)
        if codesign_identity:
            subprocess.run(
                [
                    "codesign",
                    "--force",
                    "--sign",
                    codesign_identity,
                    "--options",
                    "runtime",
                    codesign_timestamp,
                    str(destination),
                ],
                check=True,
            )
            subprocess.run(
                ["codesign", "--verify", "--strict", str(destination)],
                check=True,
            )

    workspace_root = Path(metadata["workspace_root"]).resolve()
    verify_source_identity(source_root, identity)
    manifest = {
        "schema": NATIVE_MANIFEST_SCHEMA,
        "sourceIdentity": identity,
        "hooks": [
            manifest_entry(targets[name], workspace_root) for name in sorted(hook_names)
        ],
        "additionalExecutables": [
            manifest_entry(targets[name], workspace_root) for name in additional
        ],
    }
    (release_root / "native-hook-binaries.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    )


def stage_release(
    runtime: Path,
    destination: Path,
    source_root: Path,
    replace_existing: bool,
) -> None:
    # Staging starts from an installed runtime, so a machine that has never
    # installed one - or a caller pointed at the wrong home - has to be told
    # that, rather than meeting `FileNotFoundError` from inside copytree.
    if not runtime.is_dir():
        raise RuntimeError(
            f"No installed hook runtime to stage from: {runtime}. Pass --runtime with an "
            "installed release root, or install a release on this machine first."
        )
    if destination.exists():
        if not replace_existing:
            raise RuntimeError(
                f"Refusing to overwrite explicit staging destination: {destination}"
            )
        shutil.rmtree(destination)
    shutil.copytree(runtime, destination, symlinks=True)
    for derived in (
        "release.json",
        "external-sources.json",
        "external-hooks",
        "native-hook-binaries.json",
        "bin",
    ):
        path = destination / derived
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink(missing_ok=True)
    shutil.copy2(source_root / "package.json", destination / "package.json")
    for directory in ("shared-hooks", "claude-hooks", "codex-hooks", "repo-githooks"):
        target = destination / directory
        shutil.rmtree(target, ignore_errors=True)
        shutil.copytree(source_root / directory, target)


def main() -> None:
    home = Path.home()
    project = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source-root",
        type=Path,
        default=Path(os.environ.get("TAMA_HOOK_SOURCE_ROOT") or project.parent / "tama"),
    )
    parser.add_argument(
        "--runtime",
        type=Path,
        default=home / "Library/Application Support/Tama/hooks-runtime/current",
    )
    parser.add_argument("--destination", type=Path)
    parser.add_argument(
        "--release-root",
        type=Path,
        help="Package an already prepared release instead of staging the live runtime",
    )
    parser.add_argument("--cargo", type=Path)
    parser.add_argument(
        "--include-bin",
        action="append",
        default=["tama-cli", "tama-mcp-server", "tama-run-hook"],
    )
    parser.add_argument("--codesign-identity")
    parser.add_argument("--codesign-timestamp", default="--timestamp=none")
    args = parser.parse_args()

    source_root = args.source_root.resolve()
    cargo = args.cargo or Path(os.environ.get("TAMA_CARGO") or shutil.which("cargo") or "")
    if not str(cargo) or not cargo.is_file() or not os.access(cargo, os.X_OK):
        raise RuntimeError("A usable Cargo executable is required")

    if args.release_root:
        if args.destination is not None:
            parser.error("--destination cannot be combined with --release-root")
        release_root = args.release_root.resolve()
    else:
        explicit_destination = args.destination is not None
        release_root = (
            args.destination or project / ".work/inline-hook-release"
        ).resolve()
        stage_release(
            args.runtime.resolve(),
            release_root,
            source_root,
            replace_existing=not explicit_destination,
        )

    package_native_binaries(
        release_root,
        source_root,
        cargo.absolute(),
        args.include_bin,
        args.codesign_identity,
        args.codesign_timestamp,
    )
    sys.stdout.write(str(release_root) + "\n")


if __name__ == "__main__":
    main()
