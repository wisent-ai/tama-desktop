"""Parts of install_hook_release.py, split by the tama size splitter; install_hook_release.py imports every name back."""

from __future__ import annotations
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
from install_hook_release_parts.schema.schema import INSTALLED_SCHEMA, dispatcher_body, global_hooks_path
from install_hook_release_parts.schema.transaction import Transaction


def add_git_hook_writes(
    writes: dict[Path, tuple[bytes, int]],
    home: Path,
    runtime_root: Path,
    release_root: Path,
    moved: list[tuple[Path, Path]],
    old_root: Path,
    old_home: Path,
) -> None:
    """The global Git dispatchers and every approved repository hook, into `writes`."""
    moved_by_source = {source: disabled for source, disabled in moved}
    hooks_path = global_hooks_path(home)
    stable_runtime = runtime_root / "current"
    for hook_name in ("pre-commit", "pre-push"):
        active = hooks_path / hook_name
        target = moved_by_source.get(active, active)
        backup = hooks_path / f"{hook_name}.before-tama"
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


def register_omp_adapter(home: Path, omp_adapter_target: Path) -> tuple[list | None, bool]:
    """Put the OMP adapter among OMP's extensions: (the list before, whether it changed)."""
    omp = os.environ.get("TAMA_OMP") or shutil.which("omp")
    if not omp and (home / ".local/bin/omp").is_file():
        omp = str(home / ".local/bin/omp")
    if not omp:
        return None, False
    omp_changed = False
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
    obsolete_adapters = {
        str(home / ".omp/agent/hooks/pre/shared-hooks.js"),
        str(home / ".omp/agent/hooks.tama-disabled/pre/shared-hooks.js"),
    }
    updated = [path for path in omp_previous if path not in obsolete_adapters]
    adapter_path = str(omp_adapter_target)
    if adapter_path not in updated:
        updated.append(adapter_path)
    if updated != omp_previous:
        result = subprocess.run(
            [omp, "config", "set", "extensions", json.dumps(updated)],
            capture_output=True,
            text=True,
            check=False,
            env=command_env,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "Could not register OMP hook adapter")
        omp_changed = True
    return omp_previous, omp_changed


def apply_install(
    runtime_root: Path,
    installed_release: Path,
    writes: dict[Path, tuple[bytes, int]],
    obsolete_source_files: set[Path],
    moved: list[tuple[Path, Path]],
    home: Path,
    omp_adapter_target: Path,
    release: dict,
    registry: dict,
    previous: dict,
    new_source_files: set[str],
    node_executable: Path,
    node_version: str,
) -> dict:
    """One transaction: every write, the runtime link, the restored entrypoints, OMP, the record."""
    release_id = release["releaseId"]
    installed_path = runtime_root / "installed.json"
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

        omp_previous, omp_changed = register_omp_adapter(home, omp_adapter_target)

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
            "nodeExecutable": str(node_executable),
            "nodeVersion": node_version,
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
    return installed
