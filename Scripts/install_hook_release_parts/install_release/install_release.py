"""Parts of install_hook_release.py, split by the tama size splitter; install_hook_release.py imports every name back."""

from __future__ import annotations
import argparse
import json
from pathlib import Path
from install_hook_release_parts.schema.schema import load_json
from install_hook_release_parts.schema.transaction import declared_native_binaries
from install_hook_release_parts.schema.verified_release import copied_release, installed_registry, provider_writes, refuse_entrypoint_conflicts, require_approved_sources, source_file_changes, verified_release
from install_hook_release_parts.schema.add_git_hook_writes import add_git_hook_writes, apply_install


def install_release(
    release_root: Path,
    home: Path,
    manifest_path: Path | None,
    session_control_only: bool = False,
) -> dict:
    release_root = release_root.resolve()
    release, (node_executable, node_version), registry_raw, old_root, old_home = verified_release(release_root, home)
    catalog = registry_raw.get("catalog", {})

    tama_root = home / "Library/Application Support/Tama"
    runtime_root = tama_root / "hooks-runtime"
    stable_runtime = runtime_root / "current"
    native_hooks = declared_native_binaries(
        release_root,
        registry_raw,
    )
    external_sources = load_json(release_root / "external-sources.json")
    if external_sources.get("schema") != "ai.wisent.tama.external-hook-sources.v1":
        raise RuntimeError("Unsupported external hook source manifest")
    external_mappings = external_sources.get("mappings", [])
    require_approved_sources(catalog, external_mappings, release_root, old_root, old_home, home)
    registry, node_preflight = installed_registry(
        release_root, registry_raw, release, external_mappings, old_root, old_home, home,
        stable_runtime, node_executable, native_hooks,
    )

    installed_path = runtime_root / "installed.json"
    previous = load_json(installed_path) if installed_path.is_file() else {}
    release_id = release["releaseId"]
    installed_release = copied_release(release_root, runtime_root / "releases", release_id)

    emergency_manifest = {}
    backup_root = None
    if not session_control_only:
        if manifest_path is None:
            raise RuntimeError("Full hook installation requires an emergency manifest")
        emergency_manifest = load_json(manifest_path)
        backup_root = manifest_path.parent

    writes, launcher_target, omp_adapter_target = provider_writes(
        release_root, home, registry, node_executable, node_preflight, emergency_manifest, backup_root,
    )
    legacy_launchers = {
        home / ".local/bin/tama-omp",
        home / ".local/bin/tama-agent-supervisor",
    }

    moved = [] if session_control_only else [
        (Path(item["source"]), Path(item["disabled"]))
        for item in emergency_manifest.get("moved", [])
    ]
    if not session_control_only:
        refuse_entrypoint_conflicts(moved)
        add_git_hook_writes(writes, home, runtime_root, release_root, moved, old_root, old_home)
    new_source_files, obsolete_source_files = source_file_changes(
        writes, previous, home, launcher_target, legacy_launchers,
    )
    installed = apply_install(
        runtime_root, installed_release, writes, obsolete_source_files, moved, home,
        omp_adapter_target, release, registry, previous, new_source_files, node_executable, node_version,
    )

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
