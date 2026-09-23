"""Parts of install_hook_release.py, split by the tama size splitter; install_hook_release.py imports every name back."""

from __future__ import annotations
import json
import os
from pathlib import Path
import shutil
import shlex
from install_hook_release_parts.schema.schema import SCHEMA, base_config, load_json, provider_hook_block, registry_checksum, release_file_map, source_candidate, supervisor_launcher_body, transformed, tree_digest
from install_hook_release_parts.schema.transaction import entrypoint_kind, pin_native_commands, pin_node_commands, require_supported_node


def verified_release(release_root: Path, home: Path) -> tuple[dict, tuple[Path, str], dict, Path, Path]:
    """The sealed release, the Node.js it will run on, and the roots its registry was written for."""
    release = load_json(release_root / "release.json")
    if release.get("schema") != SCHEMA:
        raise RuntimeError("Unsupported Tama hook release manifest")
    actual_digest = tree_digest(release_root)
    if release.get("releaseId") != actual_digest:
        raise RuntimeError("Bundled Tama hook release failed its integrity check")
    node = require_supported_node(home)

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
    return release, node, registry_raw, old_root, old_home


def require_approved_sources(
    catalog: dict,
    external_mappings: list,
    release_root: Path,
    old_root: Path,
    old_home: Path,
    home: Path,
) -> None:
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


def installed_registry(
    release_root: Path,
    registry_raw: dict,
    release: dict,
    external_mappings: list,
    old_root: Path,
    old_home: Path,
    home: Path,
    stable_runtime: Path,
    node_executable: Path,
    native_hooks: set[str],
) -> tuple[dict, Path]:
    """The registry rewritten for this home, with Node.js and native commands pinned."""
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
    node_preflight = stable_runtime / "shared-hooks/node-runtime-preflight.cjs"
    if not (release_root / "shared-hooks/node-runtime-preflight.cjs").is_file():
        raise RuntimeError("Approved hook release is missing the Node.js runtime preflight")
    registry = transformed(registry_raw, replacements)
    pin_node_commands(registry, node_executable, node_preflight)
    pinned_native_hooks: set[str] = set()
    pin_native_commands(
        registry,
        native_hooks,
        stable_runtime,
        pinned_native_hooks,
    )
    unreferenced_native_hooks = sorted(native_hooks - pinned_native_hooks)
    if unreferenced_native_hooks:
        raise RuntimeError(
            "Packaged native hook binaries are not referenced by the registry: "
            + ", ".join(unreferenced_native_hooks)
        )
    registry["releaseId"] = release["releaseId"]
    registry["catalog"].pop("ompAdapters", None)
    registry.pop("adapters", None)
    registry["catalog"]["generatedDocs"] = str(home / ".shared-hooks/HOOKS.md")
    registry["catalogChecksum"] = registry_checksum(registry)
    return registry, node_preflight


def copied_release(release_root: Path, releases_root: Path, release_id: str) -> Path:
    """The release's content-addressed copy under the runtime, verified after the copy."""
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
    return installed_release


def provider_writes(
    release_root: Path,
    home: Path,
    registry: dict,
    node_executable: Path,
    node_preflight: Path,
    emergency_manifest: dict,
    backup_root: Path | None,
) -> tuple[dict[Path, tuple[bytes, int]], Path, Path]:
    """Every file the release writes, with the launcher and both provider configurations."""
    writes = release_file_map(release_root, home, registry)
    supervisor_target = home / ".shared-hooks/agent-session-supervisor.py"
    if supervisor_target not in writes:
        raise RuntimeError("Approved hook release is missing the Tama session supervisor")
    runtime_target = home / ".shared-hooks/universal_agent_runtime.py"
    if runtime_target not in writes:
        raise RuntimeError("Approved hook release is missing the universal Tama runtime")
    omp_adapter_target = home / ".shared-hooks/omp-shared-hooks.js"
    if omp_adapter_target not in writes:
        raise RuntimeError("Approved hook release is missing the OMP Tama adapter")
    launcher_target = home / ".local/bin/tama-agent"
    writes[launcher_target] = (supervisor_launcher_body(home, node_executable), 0o755)
    dispatcher_target = home / ".shared-hooks/run-hook.mjs"
    if dispatcher_target not in writes:
        raise RuntimeError("Approved hook release is missing the Tama hook dispatcher")
    claude_target = home / ".claude/settings.json"
    codex_target = home / ".codex/hooks.json"
    # The same pinned Node the registry commands carry, running the installed
    # dispatcher: a provider event reaches exactly the runtime this install
    # wrote, and `tama validate` can see that it does.
    dispatcher = (
        f"{shlex.quote(str(node_executable))} --require {shlex.quote(str(node_preflight))} "
        + shlex.quote(str(dispatcher_target))
    )
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
    claude_config["hooks"] = provider_hook_block(
        release_root, registry, "claude", dispatcher
    )
    codex_config["hooks"] = provider_hook_block(
        release_root, registry, "codex", dispatcher
    )
    writes[claude_target] = (
        (json.dumps(claude_config, indent=2, sort_keys=True) + "\n").encode(),
        0o600,
    )
    writes[codex_target] = (
        (json.dumps(codex_config, indent=2, sort_keys=True) + "\n").encode(),
        0o600,
    )
    return writes, launcher_target, omp_adapter_target


def refuse_entrypoint_conflicts(moved: list[tuple[Path, Path]]) -> None:
    # Every conflict, in one refusal. `Transaction.move` fails on the first
    # pair whose active file and `.tama-disabled` sibling both exist, so an
    # operator restoring policy after something rewrote an entrypoint during
    # the bypass learned about them one failed run at a time. Reading them all
    # here costs one pass and tells the whole truth; the fail-closed behaviour
    # below is unchanged, and nothing is installed either way.
    conflicts = [
        (source, disabled)
        for source, disabled in moved
        if (source.exists() or source.is_symlink())
        and (disabled.exists() or disabled.is_symlink())
    ]
    if conflicts:
        lines = [
            f"{len(conflicts)} hook entrypoint(s) exist both active and disabled; "
            "resolve each one before restoring policy:"
        ]
        for source, disabled in conflicts:
            lines.append(f"  {source} ({entrypoint_kind(source)})")
            lines.append(f"    disabled copy: {disabled}")
        raise RuntimeError("\n".join(lines))


def source_file_changes(
    writes: dict[Path, tuple[bytes, int]],
    previous: dict,
    home: Path,
    launcher_target: Path,
    legacy_launchers: set[Path],
) -> tuple[set[str], set[Path]]:
    """The managed files this install writes, and the ones the previous install wrote that go."""
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
    return new_source_files, obsolete_source_files
