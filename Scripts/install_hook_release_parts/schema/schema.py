"""Parts of install_hook_release.py, split by the tama size splitter; install_hook_release.py imports every name back."""

from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess


SCHEMA = "ai.wisent.tama.hook-release.v1"
INSTALLED_SCHEMA = "ai.wisent.tama.installed-hook-release.v1"
NATIVE_MANIFEST_SCHEMA = "ai.wisent.tama.native-hook-binaries.v1"

MINIMUM_NODE_MAJOR = 20
# `node --version` answers at once; a candidate that takes longer is not a working runtime.
NODE_VERSION_PROBE_TIMEOUT_SECONDS = 5
# A declared native binary must carry an execute bit for someone.
EXECUTABLE_MODE_BITS = 0o111


def atomic_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".tama-{os.getpid()}")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    os.replace(temporary, path)


def registry_checksum(registry: dict) -> str:
    value = {key: item for key, item in registry.items() if key != "catalogChecksum"}
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file() and item.name != "release.json"):
        relative = path.relative_to(root).as_posix().encode()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        mode = path.stat().st_mode & 0o777
        digest.update(mode.to_bytes(4, "big"))
        data = path.read_bytes()
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
    return digest.hexdigest()


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected a JSON object: {path}")
    return value


def transformed(value, replacements: list[tuple[str, str]], field: str | None = None):
    if isinstance(value, str):
        markers = []
        for index, (source, target) in enumerate(replacements):
            marker = f"\u0000TAMA_PATH_{index}\u0000"
            value = value.replace(source, marker)
            replacement = shlex.quote(target) if field == "command" else target
            markers.append((marker, replacement))
        for marker, target in markers:
            value = value.replace(marker, target)
        return value
    if isinstance(value, list):
        return [transformed(item, replacements, field) for item in value]
    if isinstance(value, dict):
        return {key: transformed(item, replacements, key) for key, item in value.items()}
    return value




def source_candidate(source: str, release_root: Path, old_root: Path, old_home: Path, home: Path) -> Path:
    source_path = Path(source)
    mappings = (
        (old_root / "shared-hooks", release_root / "shared-hooks"),
        (old_root / "claude-hooks", release_root / "claude-hooks"),
        (old_root / "codex-hooks", release_root / "codex-hooks"),
        (old_home / ".shared-hooks", release_root / "shared-hooks"),
        (old_home / ".claude/hooks", release_root / "claude-hooks"),
        (old_home / ".codex/hooks", release_root / "codex-hooks"),
    )
    for source_base, release_base in mappings:
        try:
            return release_base / source_path.relative_to(source_base)
        except ValueError:
            pass
    try:
        return home / source_path.relative_to(old_home)
    except ValueError:
        return source_path


def release_file_map(release_root: Path, home: Path, registry: dict) -> dict[Path, tuple[bytes, int]]:
    files: dict[Path, tuple[bytes, int]] = {}
    roots = (
        (release_root / "shared-hooks", home / ".shared-hooks"),
        (release_root / "claude-hooks", home / ".claude/hooks"),
        (release_root / "codex-hooks", home / ".codex/hooks"),
    )
    for source_root, target_root in roots:
        for source in sorted(
            item
            for item in source_root.rglob("*")
            if item.is_file()
            and item.suffix != ".pyc"
            and "__pycache__" not in item.parts
            and item.name not in {
                "generate-configs.mjs",
                "providers.json",
                "run-one-session-hook.js",
            }
        ):
            target = target_root / source.relative_to(source_root)
            files[target] = (source.read_bytes(), source.stat().st_mode & 0o777)
    registry_target = home / ".shared-hooks/registry.json"
    files[registry_target] = (
        (json.dumps(registry, indent=2, sort_keys=True) + "\n").encode(),
        0o644,
    )
    return files


def base_config(
    target: Path,
    label: str,
    emergency_manifest: dict,
    backup_root: Path | None,
) -> dict:
    configured = set(emergency_manifest.get("configs", []))
    saved = backup_root / label if backup_root is not None else None
    source = (
        saved
        if saved is not None and str(target) in configured and saved.is_file()
        else target
    )
    if not source.is_file():
        return {}
    return load_json(source)


def provider_hook_block(
    release_root: Path,
    registry: dict,
    provider: str,
    dispatcher: str,
) -> dict:
    """The wiring `~/.claude/settings.json` and `~/.codex/hooks.json` carry.

    The sealed CLI owns the event/matcher table and the command shape, so a
    release cannot install a provider config that disagrees with the registry
    it installed beside it. It refuses rather than return an empty block, and
    an empty block is what left both providers enforcing nothing.
    """
    cli = release_root / "bin/tama"
    if not cli.is_file() or not os.access(cli, os.X_OK):
        raise RuntimeError("Approved hook release is missing the sealed Tama CLI")
    result = subprocess.run(
        [
            str(cli),
            "provider-config",
            "--provider",
            provider,
            "--dispatcher",
            dispatcher,
            "--json",
        ],
        input=json.dumps(registry).encode(),
        capture_output=True,
        check=False,
    )
    if result.returncode != os.EX_OK:
        detail = (result.stderr or b"").decode(errors="replace").strip().splitlines()
        raise RuntimeError(
            f"Provider config generation failed for {provider}: "
            + (detail.pop() if detail else "no diagnostic")
        )
    try:
        block = json.loads(result.stdout.decode())
    except ValueError as error:
        raise RuntimeError(
            f"Provider config generation failed for {provider}: unreadable block: {error}"
        ) from error
    if not isinstance(block, dict) or not block:
        raise RuntimeError(
            f"Provider config generation failed for {provider}: empty hook block"
        )
    return block



def dispatcher_body(runtime_root: Path, hook_name: str, backup_path: Path) -> bytes:
    repo_hook = "${repo_root}/.githooks/" + hook_name
    body = f'''#!/bin/sh
# tama managed global Git dispatcher
set -eu
ROOT={shlex.quote(str(runtime_root))}
HOOK_NAME={shlex.quote(hook_name)}
BACKUP={shlex.quote(str(backup_path))}
INPUT_FILE="${{TMPDIR:-/tmp}}/tama-$HOOK_NAME-$$.stdin"
cat > "$INPUT_FILE"
trap 'rm -f "$INPUT_FILE"' EXIT
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
archive_hook=''
if [ -n "$repo_root" ]; then
  repo_base="$(basename "$repo_root")"
  archive_hook="$ROOT/repo-githooks/$repo_base/$HOOK_NAME"
fi
if [ -n "$repo_root" ] && [ -x "{repo_hook}" ]; then
  "{repo_hook}" "$@" < "$INPUT_FILE"
elif [ -n "$archive_hook" ] && [ -x "$archive_hook" ]; then
  "$archive_hook" "$@" < "$INPUT_FILE"
fi
if [ -x "$BACKUP" ]; then
  "$BACKUP" "$@" < "$INPUT_FILE"
fi
exit 0
'''
    return body.encode()


def supervisor_launcher_body(home: Path, node_executable: Path) -> bytes:
    supervisor = home / ".shared-hooks/agent-session-supervisor.py"
    node_preflight = (
        home
        / "Library/Application Support/Tama/hooks-runtime/current/shared-hooks"
        / "node-runtime-preflight.cjs"
    )
    body = f'''#!/bin/sh
# Tama-managed universal process and semantic hook runtime
set -eu
SUPERVISOR={shlex.quote(str(supervisor))}
NODE={shlex.quote(str(node_executable))}
PREFLIGHT={shlex.quote(str(node_preflight))}
[ -f "$PREFLIGHT" ] || {{ printf 'Tama Node.js runtime preflight is missing: %s\\n' "$PREFLIGHT" >&{int("2")}; exit {int("66")}; }}
[ -x "$NODE" ] || {{ printf 'Tama requires its validated Node.js executable: %s\\n' "$NODE" >&{int("2")}; exit {int("66")}; }}
export TAMA_NODE_EXECUTABLE="$NODE"
export TAMA_NODE_PREFLIGHT="$PREFLIGHT"
[ -x "$SUPERVISOR" ] || {{ printf 'Tama session supervisor is missing: %s\\n' "$SUPERVISOR" >&2; exit 66; }}
PYTHON="${{TAMA_PYTHON:-$(command -v python3 || true)}}"
[ -n "$PYTHON" ] || {{ printf 'Tama requires Python 3 for the universal session runtime.\\n' >&2; exit 66; }}
exec "$PYTHON" "$SUPERVISOR" "$@"
'''
    return body.encode()


def global_hooks_path(home: Path) -> Path:
    result = subprocess.run(
        ["git", "config", "--global", "--get", "core.hooksPath"],
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "HOME": str(home)},
    )
    value = result.stdout.strip() if result.returncode == 0 else ""
    if not value:
        return home / ".config/git/hooks"
    if value == "~":
        return home
    if value.startswith("~/"):
        return home / value[2:]
    return Path(value).expanduser()
