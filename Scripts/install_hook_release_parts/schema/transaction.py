"""Parts of install_hook_release.py, split by the tama size splitter; install_hook_release.py imports every name back."""

from __future__ import annotations
import os
from pathlib import Path
import shutil
import shlex
import subprocess
from install_hook_release_parts.schema.schema import EXECUTABLE_MODE_BITS, MINIMUM_NODE_MAJOR, NATIVE_MANIFEST_SCHEMA, NODE_VERSION_PROBE_TIMEOUT_SECONDS, load_json


class Transaction:
    def __init__(self, backup_root: Path):
        self.backup_root = backup_root
        self.backup_root.mkdir(parents=True, exist_ok=False)
        self.originals: list[tuple[Path, Path | None]] = []
        self.original_paths: set[Path] = set()
        self.moves: list[tuple[Path, Path]] = []

    def remember(self, path: Path) -> None:
        if path in self.original_paths:
            return
        self.original_paths.add(path)
        if path.exists() or path.is_symlink():
            backup = self.backup_root / str(len(self.originals))
            if path.is_dir() and not path.is_symlink():
                shutil.copytree(path, backup, symlinks=True)
            else:
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, backup, follow_symlinks=False)
            self.originals.append((path, backup))
        else:
            self.originals.append((path, None))

    def write(self, path: Path, data: bytes, mode: int) -> None:
        self.remember(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(path.name + f".tama-install-{os.getpid()}")
        temporary.write_bytes(data)
        os.chmod(temporary, mode)
        os.replace(temporary, path)

    def delete(self, path: Path) -> None:
        self.remember(path)
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink(missing_ok=True)

    def move(self, disabled: Path, source: Path) -> None:
        if source.exists() or source.is_symlink():
            raise RuntimeError(f"Both active and disabled hook entrypoints exist: {source}")
        if not disabled.exists() and not disabled.is_symlink():
            raise RuntimeError(f"Missing disabled hook entrypoint: {disabled}")
        source.parent.mkdir(parents=True, exist_ok=True)
        os.replace(disabled, source)
        self.moves.append((source, disabled))

    def rollback(self) -> None:
        for source, disabled in reversed(self.moves):
            if source.exists() or source.is_symlink():
                disabled.parent.mkdir(parents=True, exist_ok=True)
                os.replace(source, disabled)
        for path, backup in reversed(self.originals):
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink(missing_ok=True)
            if backup is None:
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            if backup.is_dir() and not backup.is_symlink():
                shutil.copytree(backup, path, symlinks=True)
            else:
                shutil.copy2(backup, path, follow_symlinks=False)


def require_supported_node(home: Path) -> tuple[Path, str]:
    discovered = shutil.which("node")
    candidates = ([Path(discovered)] if discovered else []) + [
        Path("/opt/homebrew/bin/node"),
        Path("/usr/local/bin/node"),
        home / ".local/bin/node",
    ]
    unsupported_versions = []
    visited = set()
    for candidate in candidates:
        key = str(candidate)
        if key in visited:
            continue
        visited.add(key)
        if not candidate.is_file() or not os.access(candidate, os.X_OK):
            continue
        try:
            result = subprocess.run(
                [str(candidate), "--version"],
                capture_output=True,
                text=True,
                check=False,
                timeout=NODE_VERSION_PROBE_TIMEOUT_SECONDS,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        version = (result.stdout or result.stderr).strip()
        normalized = version.removeprefix("v")
        try:
            major = int(normalized.split(".", maxsplit=int("1"))[int("0")])
        except (TypeError, ValueError):
            continue
        if result.returncode == int("0") and major >= MINIMUM_NODE_MAJOR:
            try:
                return candidate.resolve(strict=True), version
            except OSError:
                continue
        if version:
            unsupported_versions.append(version)
    if unsupported_versions:
        found = ", ".join(unsupported_versions)
        raise RuntimeError(
            f"Node.js {MINIMUM_NODE_MAJOR} or newer is required; found {found}"
        )
    raise RuntimeError(
        f"Node.js {MINIMUM_NODE_MAJOR} or newer is required on PATH, "
        "/opt/homebrew/bin, /usr/local/bin, or ~/.local/bin"
    )


def pin_node_commands(registry: dict, node: Path, preflight: Path) -> None:
    hook_groups = [
        config.get("hooks", [])
        for config in registry.get("events", {}).values()
        if isinstance(config, dict)
    ]
    hook_groups.append(registry.get("catalog", {}).get("agentHooks", []))
    node_command = f"{shlex.quote(str(node))} --require {shlex.quote(str(preflight))}"
    for hooks in hook_groups:
        if not isinstance(hooks, list):
            continue
        for hook in hooks:
            if not isinstance(hook, dict):
                continue
            command = hook.get("command")
            if isinstance(command, str) and (
                command == "node" or command.startswith("node ")
            ):
                hook["command"] = node_command + command[len("node"):]

def command_arguments(command: str) -> list[str]:
    try:
        arguments = shlex.split(command)
    except ValueError as error:
        raise RuntimeError(f"Invalid hook command {command!r}: {error}") from error
    if not arguments:
        raise RuntimeError("Hook command cannot be empty")
    return arguments


def native_command_names(value: object) -> set[str]:
    names: set[str] = set()
    if isinstance(value, dict):
        command = value.get("command")
        source = value.get("source")
        if isinstance(command, str):
            name = Path(command_arguments(command)[0]).name
            if name.startswith("tama-") or (
                isinstance(source, str) and source.endswith(".rs")
            ):
                names.add(name)
        for nested in value.values():
            names.update(native_command_names(nested))
    elif isinstance(value, list):
        for nested in value:
            names.update(native_command_names(nested))
    return names




def declared_native_binaries(
    release_root: Path,
    registry: dict,
) -> set[str]:
    manifest_path = release_root / "native-hook-binaries.json"
    manifest = load_json(manifest_path)
    if manifest.get("schema") != NATIVE_MANIFEST_SCHEMA:
        raise RuntimeError("Unsupported native hook binary manifest")

    groups: dict[str, set[str]] = {}
    all_names: set[str] = set()
    for field in ("hooks", "additionalExecutables"):
        entries = manifest.get(field)
        if not isinstance(entries, list):
            raise RuntimeError(f"Native hook binary manifest is missing {field}")
        names: set[str] = set()
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
                raise RuntimeError(f"Native hook binary manifest has an invalid {field} entry")
            name = entry["name"]
            package = entry.get("package")
            source = entry.get("source")
            if not isinstance(package, str) or not isinstance(source, str):
                raise RuntimeError(
                    f"Native hook binary manifest lacks build identity for {name}"
                )
            if field == "hooks" and not source.endswith(".rs"):
                raise RuntimeError(f"Native hook source is not Rust: {name}: {source}")
            if Path(name).name != name or not name.startswith("tama-"):
                raise RuntimeError(f"Invalid declared native binary name: {name}")
            if name in all_names:
                raise RuntimeError(f"Duplicate declared native binary: {name}")
            binary = release_root / "bin" / name
            if not binary.is_file() or not (binary.stat().st_mode & EXECUTABLE_MODE_BITS):
                raise RuntimeError(f"Declared native binary is missing or not executable: {name}")
            names.add(name)
            all_names.add(name)
        groups[field] = names

    undeclared = sorted(native_command_names(registry) - groups["hooks"])
    if undeclared:
        raise RuntimeError(
            "Registry native hook commands lack packaged binaries: "
            + ", ".join(undeclared)
        )
    return groups["hooks"]


def pin_native_commands(
    value: object,
    native_hooks: set[str],
    stable_runtime: Path,
    seen: set[str],
) -> None:
    if isinstance(value, dict):
        command = value.get("command")
        if isinstance(command, str):
            arguments = command_arguments(command)
            name = Path(arguments[0]).name
            if name in native_hooks:
                arguments[0] = str(stable_runtime / "bin" / name)
                value["command"] = shlex.join(arguments)
                seen.add(name)
        for nested in value.values():
            pin_native_commands(nested, native_hooks, stable_runtime, seen)
    elif isinstance(value, list):
        for nested in value:
            pin_native_commands(nested, native_hooks, stable_runtime, seen)


MANAGED_DISPATCHER_MARKER = "tama managed"


def entrypoint_kind(path: Path) -> str:
    """What an active entrypoint is, in the terms an operator decides in.

    A Tama-managed dispatcher at that path is something the product wrote and
    this installer would rewrite anyway; anything else is a person's file and
    the decision is theirs. `Scripts/entrypoints/report_conflicts.py` answers
    the same two ways, so the refusal and the report agree. Only the header is
    read: the marker is on the dispatcher's own comment line.
    """
    try:
        with path.open(errors="replace") as handle:
            head = "".join(handle.readline() for _ in MANAGED_DISPATCHER_MARKER)
    except OSError as error:
        return f"unreadable: {error}"
    return (
        "tama-managed dispatcher"
        if MANAGED_DISPATCHER_MARKER in head
        else "not Tama-managed"
    )
