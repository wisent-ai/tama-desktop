#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys

SCHEMA = "ai.wisent.tama.hook-release.v1"
INSTALLED_SCHEMA = "ai.wisent.tama.installed-hook-release.v1"
EVENT_TO_CODEX = {
    "stop": ("Stop", None),
    "user_prompt_submit": ("UserPromptSubmit", None),
    "post_tool_use:bash": ("PostToolUse", "Bash"),
    "session_start:compact": ("SessionStart", "compact"),
    "pre_tool_use:bash": ("PreToolUse", "Bash"),
    "pre_tool_use:read": ("PreToolUse", "Read"),
    "pre_tool_use:edit": ("PreToolUse", "apply_patch|Edit|Write"),
    "pre_tool_use:task": ("PreToolUse", "Task|Agent"),
    "pre_tool_use:todo": ("PreToolUse", "Todo|todo"),
    "pre_tool_use:goal": ("PreToolUse", "Goal|goal"),
    "pre_tool_use:lookup": ("PreToolUse", "Grep|grep|Glob|glob|Search|LSP|lsp|AstGrep|ast_grep"),
    "pre_tool_use:notebook": ("PreToolUse", "NotebookEdit"),
    "pre_tool_use:wait": ("PreToolUse", "Monitor|ScheduleWakeup"),
    "pre_tool_use:eval": ("PreToolUse", "Eval|eval|execute_code|mcp__node_repl_js|node_repl/js"),
    "pre_tool_use:ssh": ("PreToolUse", "SSH|ssh"),
}


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


def hook_config(event: str, hook: dict, provider: str) -> dict:
    command = " ".join(
        [
            "env",
            f"TAMA_PROVIDER={shlex.quote(provider)}",
            f"TAMA_ONLY_HOOK_ID={shlex.quote(str(hook['id']))}",
            'node \"$HOME/.shared-hooks/run-hook.mjs\"',
            shlex.quote(event),
            shlex.quote(provider),
        ]
    )
    result = {"type": hook.get("type") or "command", "command": command}
    if hook.get("timeout"):
        result["timeout"] = hook["timeout"]
    if hook.get("statusMessage"):
        result["statusMessage"] = hook["statusMessage"]
    return result


def build_hooks(registry: dict, provider: str) -> dict:
    result: dict[str, list[dict]] = {}
    for event, entry in registry.get("events", {}).items():
        target = EVENT_TO_CODEX.get(event)
        if target is None:
            continue
        key, matcher = target
        group = {
            "hooks": [
                hook_config(event, hook, provider)
                for hook in entry.get("hooks", [])
            ]
        }
        if matcher:
            group["matcher"] = matcher
        result.setdefault(key, []).append(group)
    return result


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


def dispatcher_body(runtime_root: Path, hook_name: str, backup_path: Path) -> bytes:
    repo_hook = "${repo_root}/.githooks/" + hook_name
    body = f'''#!/bin/sh
# hooks-rotator managed global Git dispatcher
set -eu
ROOT={json.dumps(str(runtime_root))}
HOOK_NAME={json.dumps(hook_name)}
BACKUP={json.dumps(str(backup_path))}
INPUT_FILE="${{TMPDIR:-/tmp}}/hooks-rotator-$HOOK_NAME-$$.stdin"
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


def supervisor_launcher_body(home: Path) -> bytes:
    supervisor = home / ".shared-hooks/agent-session-supervisor.py"
    body = f'''#!/bin/sh
# Tama-managed process and session supervisor
set -eu
SUPERVISOR={json.dumps(str(supervisor))}
[ -x "$SUPERVISOR" ] || {{ printf 'Tama session supervisor is missing: %s\\n' "$SUPERVISOR" >&2; exit 66; }}
exec /usr/bin/python3 "$SUPERVISOR" "$@"
'''
    return body.encode()


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


def install_release(
    release_root: Path,
    home: Path,
    manifest_path: Path | None,
    session_control_only: bool = False,
) -> dict:
    release_root = release_root.resolve()
    release = load_json(release_root / "release.json")
    if release.get("schema") != SCHEMA:
        raise RuntimeError("Unsupported Tama hook release manifest")
    actual_digest = tree_digest(release_root)
    if release.get("releaseId") != actual_digest:
        raise RuntimeError("Bundled Tama hook release failed its integrity check")

    registry_raw = load_json(release_root / "shared-hooks/registry.json")
    catalog = registry_raw.get("catalog", {})
    maintained_in = Path(catalog.get("maintainedIn", ""))
    if maintained_in.name != "registry.json" or maintained_in.parent.name != "shared-hooks":
        raise RuntimeError("Hook registry does not identify its canonical source root")
    old_root = maintained_in.parent.parent
    codex_path = Path(registry_raw.get("adapters", {}).get("codex", {}).get("path", ""))
    if codex_path.name != "hooks.json" or codex_path.parent.name != ".codex":
        raise RuntimeError("Hook registry does not identify its canonical home")
    old_home = codex_path.parent.parent

    tama_root = home / "Library/Application Support/Tama"
    runtime_root = tama_root / "hooks-runtime"
    stable_runtime = runtime_root / "current"
    external_sources = load_json(release_root / "external-sources.json")
    if external_sources.get("schema") != "ai.wisent.tama.external-hook-sources.v1":
        raise RuntimeError("Unsupported external hook source manifest")
    external_mappings = external_sources.get("mappings", [])

    for hook in catalog.get("agentHooks", []):
        source = hook.get("source")
        if not source:
            continue
        candidate = None
        source_path = Path(source)
        for mapping in external_mappings:
            prefix = Path(mapping["sourcePrefix"])
            try:
                candidate = (
                    release_root
                    / mapping["releasePath"]
                    / source_path.relative_to(prefix)
                )
                break
            except ValueError:
                pass
        if candidate is None:
            candidate = source_candidate(source, release_root, old_root, old_home, home)
        if not candidate.is_file():
            raise RuntimeError(f"Approved hook source is missing: {hook.get('id')}: {source}")

    replacements = [
        (
            mapping["sourcePrefix"],
            str(stable_runtime / mapping["releasePath"]),
        )
        for mapping in external_mappings
    ]
    replacements.extend(
        [
            (str(old_root / "shared-hooks"), str(home / ".shared-hooks")),
            (str(old_root / "claude-hooks"), str(home / ".claude/hooks")),
            (str(old_root / "codex-hooks"), str(home / ".codex/hooks")),
            (str(old_home), str(home)),
        ]
    )
    replacements.sort(key=lambda item: len(item[0]), reverse=True)
    registry = transformed(registry_raw, replacements)
    registry["releaseId"] = release["releaseId"]
    registry.setdefault("catalog", {})["maintainedIn"] = str(home / ".shared-hooks/registry.json")
    registry["catalog"]["generatedDocs"] = str(home / ".shared-hooks/HOOKS.md")
    registry["catalogChecksum"] = registry_checksum(registry)
    claude_hooks = build_hooks(registry, "claude")
    codex_hooks = build_hooks(registry, "codex")
    if not claude_hooks or not codex_hooks:
        raise RuntimeError("Approved hook release generated an empty runtime configuration")

    releases_root = runtime_root / "releases"
    installed_path = runtime_root / "installed.json"
    previous = load_json(installed_path) if installed_path.is_file() else {}
    release_id = release["releaseId"]
    installed_release = releases_root / release_id
    if installed_release.exists() and tree_digest(installed_release) != release_id:
        shutil.rmtree(installed_release)
    if not installed_release.exists():
        releases_root.mkdir(parents=True, exist_ok=True)
        temporary_release = releases_root / f".{release_id}-{os.getpid()}"
        shutil.rmtree(temporary_release, ignore_errors=True)
        shutil.copytree(release_root, temporary_release, symlinks=True)
        os.replace(temporary_release, installed_release)
    if tree_digest(installed_release) != release_id:
        raise RuntimeError("Installed Tama hook release failed its integrity check")

    emergency_manifest = {}
    backup_root = None
    if not session_control_only:
        if manifest_path is None:
            raise RuntimeError("Full hook installation requires an emergency manifest")
        emergency_manifest = load_json(manifest_path)
        backup_root = manifest_path.parent

    writes = release_file_map(release_root, home, registry)
    supervisor_target = home / ".shared-hooks/agent-session-supervisor.py"
    if supervisor_target not in writes:
        raise RuntimeError("Approved hook release is missing the Tama session supervisor")
    launcher_target = home / ".local/bin/tama-agent"
    writes[launcher_target] = (supervisor_launcher_body(home), 0o755)
    legacy_launchers = {
        home / ".local/bin/tama-omp",
        home / ".local/bin/tama-agent-supervisor",
    }
    claude_target = home / ".claude/settings.json"
    codex_target = home / ".codex/hooks.json"
    claude_config = base_config(
        claude_target,
        "claude-settings.json",
        emergency_manifest,
        backup_root,
    )
    codex_config = base_config(
        codex_target,
        "codex-hooks.json",
        emergency_manifest,
        backup_root,
    )
    claude_config["hooks"] = claude_hooks
    codex_config["hooks"] = codex_hooks
    writes[claude_target] = (
        (json.dumps(claude_config, indent=2, sort_keys=True) + "\n").encode(),
        0o600,
    )
    writes[codex_target] = (
        (json.dumps(codex_config, indent=2, sort_keys=True) + "\n").encode(),
        0o600,
    )

    moved = [] if session_control_only else [
        (Path(item["source"]), Path(item["disabled"]))
        for item in emergency_manifest.get("moved", [])
    ]
    moved_by_source = {source: disabled for source, disabled in moved}

    if not session_control_only:
        hooks_path = global_hooks_path(home)
        stable_runtime = runtime_root / "current"
        for hook_name in ("pre-commit", "pre-push"):
            active = hooks_path / hook_name
            target = moved_by_source.get(active, active)
            backup = hooks_path / f"{hook_name}.before-hooks-rotator"
            writes[target] = (dispatcher_body(stable_runtime, hook_name, backup), 0o755)

        repo_hook_targets: set[Path] = set()
        for source, disabled in moved:
            if source.parent.name != ".githooks":
                continue
            approved = release_root / "repo-githooks" / source.parent.parent.name / source.name
            if not approved.is_file():
                raise RuntimeError(f"Approved repository hook is missing: {approved}")
            writes[disabled] = (approved.read_bytes(), approved.stat().st_mode & 0o777)
            repo_hook_targets.add(source)

        try:
            wisent_root = home / old_root.parent.relative_to(old_home)
        except ValueError:
            wisent_root = None
        if wisent_root is not None:
            for project_release in sorted(
                item for item in (release_root / "repo-githooks").iterdir()
                if item.is_dir()
            ):
                project_candidates = (
                    wisent_root / project_release.name,
                    wisent_root / "backends" / project_release.name,
                )
                project_root = next(
                    (candidate for candidate in project_candidates if candidate.is_dir()),
                    None,
                )
                if project_root is None:
                    continue
                for approved in sorted(item for item in project_release.iterdir() if item.is_file()):
                    active = project_root / ".githooks" / approved.name
                    if active in repo_hook_targets:
                        continue
                    target = moved_by_source.get(active, active)
                    writes[target] = (
                        approved.read_bytes(),
                        approved.stat().st_mode & 0o777,
                    )
    managed_launchers = {launcher_target}
    new_source_files = {
        str(path)
        for path in writes
        if path.is_relative_to(home / ".shared-hooks")
        or path.is_relative_to(home / ".claude/hooks")
        or path.is_relative_to(home / ".codex/hooks")
        or path in managed_launchers
    }
    obsolete_source_files = {
        Path(path)
        for path in previous.get("sourceFiles", [])
        if path not in new_source_files
    }
    safe_roots = (home / ".shared-hooks", home / ".claude/hooks", home / ".codex/hooks")
    for path in obsolete_source_files:
        if path not in managed_launchers | legacy_launchers and not any(path.is_relative_to(root) for root in safe_roots):
            raise RuntimeError(f"Refusing to remove an obsolete path outside managed roots: {path}")

    transaction_root = runtime_root / f"transaction-{os.getpid()}"
    transaction = Transaction(transaction_root)
    previous_link = None
    current_link = runtime_root / "current"
    omp_previous = None
    omp_changed = False
    old_omp_adapters = (
        home / ".omp/agent/hooks/pre/shared-hooks.js",
        home / ".omp/agent/hooks.tama-disabled/pre/shared-hooks.js",
    )
    legacy_restart_artifacts = (
        home / "Library/Application Support/Tama/vscode-resume",
        home / ".vscode/extensions/tama.emergency-resume-1.0.0",
    )
    try:
        for path in sorted(obsolete_source_files, key=str):
            if path.exists() or path.is_symlink():
                transaction.delete(path)
        for path in old_omp_adapters:
            if path.exists() or path.is_symlink():
                transaction.delete(path)
        for path in legacy_restart_artifacts:
            if path.exists() or path.is_symlink():
                transaction.delete(path)
        for path, (data, mode) in sorted(writes.items(), key=lambda item: str(item[0])):
            transaction.write(path, data, mode)

        if current_link.is_symlink():
            previous_link = os.readlink(current_link)
        elif current_link.exists():
            raise RuntimeError(f"Tama runtime current path is not a symlink: {current_link}")
        temporary_link = runtime_root / f".current-{os.getpid()}"
        temporary_link.unlink(missing_ok=True)
        os.symlink(installed_release, temporary_link)
        os.replace(temporary_link, current_link)

        for source, disabled in moved:
            transaction.move(disabled, source)

        if os.environ.get("TAMA_SKIP_OMP_CONFIG") != "1":
            omp = os.environ.get("TAMA_OMP") or shutil.which("omp")
            if not omp and (home / ".local/bin/omp").is_file():
                omp = str(home / ".local/bin/omp")
            if not omp:
                raise RuntimeError("Could not locate omp to register the approved hook adapter")
            command_env = {**os.environ, "HOME": str(home)}
            current = subprocess.run(
                [omp, "config", "get", "extensions", "--json"],
                capture_output=True,
                text=True,
                check=False,
                env=command_env,
            )
            if current.returncode != 0:
                raise RuntimeError(current.stderr.strip() or "Could not read OMP extensions")
            parsed = json.loads(current.stdout or "{}")
            omp_previous = parsed.get("value") if isinstance(parsed.get("value"), list) else []
            old_adapter = str(home / ".omp/agent/hooks/pre/shared-hooks.js")
            stable_adapter = str(home / ".shared-hooks/omp-shared-hooks.js")
            updated = [path for path in omp_previous if path != old_adapter]
            if stable_adapter not in updated:
                updated.append(stable_adapter)
            if updated != omp_previous:
                result = subprocess.run(
                    [omp, "config", "set", "extensions", json.dumps(updated)],
                    capture_output=True,
                    text=True,
                    check=False,
                    env=command_env,
                )
                if result.returncode != 0:
                    raise RuntimeError(result.stderr.strip() or "Could not register OMP session controller")
                omp_changed = True

        installed = {
            "schema": INSTALLED_SCHEMA,
            "releaseId": release_id,
            "catalogChecksum": registry["catalogChecksum"],
            "packageVersion": release.get("packageVersion"),
            "catalogVersion": release.get("catalogVersion"),
            "catalogUpdatedAt": release.get("catalogUpdatedAt"),
            "installedAt": datetime.now(timezone.utc).isoformat(),
            "previousReleaseId": previous.get("releaseId"),
            "sourceFiles": sorted(new_source_files),
        }
        transaction.write(installed_path, (json.dumps(installed, indent=2, sort_keys=True) + "\n").encode(), 0o600)
    except Exception:
        if omp_changed and omp_previous is not None:
            omp = os.environ.get("TAMA_OMP") or shutil.which("omp") or str(home / ".local/bin/omp")
            subprocess.run(
                [omp, "config", "set", "extensions", json.dumps(omp_previous)],
                capture_output=True,
                text=True,
                check=False,
                env={**os.environ, "HOME": str(home)},
            )
        transaction.rollback()
        if previous_link is None:
            current_link.unlink(missing_ok=True)
        else:
            replacement = runtime_root / f".current-rollback-{os.getpid()}"
            replacement.unlink(missing_ok=True)
            os.symlink(previous_link, replacement)
            os.replace(replacement, current_link)
        raise
    finally:
        shutil.rmtree(transaction_root, ignore_errors=True)

    return {
        "installed": installed,
        "previous": previous or None,
        "managedSourceFiles": len(new_source_files),
        "restoredEntrypoints": len(moved),
        "sessionControlOnly": session_control_only,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", required=True)
    parser.add_argument("--home", required=True)
    parser.add_argument("--emergency-manifest")
    parser.add_argument("--session-control-only", action="store_true")
    args = parser.parse_args()
    manifest_path = Path(args.emergency_manifest) if args.emergency_manifest else None
    result = install_release(
        Path(args.release),
        Path(args.home),
        manifest_path,
        session_control_only=args.session_control_only,
    )
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Tama hook release installation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
