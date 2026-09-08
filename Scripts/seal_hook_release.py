#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys
import shutil


def prune_ignored(root: Path) -> None:
    for directory in sorted(root.rglob("__pycache__"), reverse=True):
        if directory.is_dir():
            shutil.rmtree(directory)
    for path in root.rglob("*.pyc"):
        path.unlink(missing_ok=True)


def package_external_sources(root: Path, registry: dict, source_root: Path) -> None:
    """Copy every hook source living outside the managed hook directories.

    `source_root` is the checkout the registry was sealed from. It has to be
    stated: since the registry became portable, `catalog.maintainedIn` reads
    `shared-hooks/registry.json`, so the root derived from it is whatever
    directory the sealer happened to run in. That made a release sealable from
    one directory and impossible from any other, and the message said only
    that a source file was missing.
    """
    catalog = registry.get("catalog", {})
    codex_path = Path(
        os.path.expandvars(registry.get("adapters", {}).get("codex", {}).get("path", ""))
    ).expanduser()
    source_home = codex_path.parent.parent
    managed_roots = (
        source_root / "shared-hooks",
        source_root / "claude-hooks",
        source_root / "codex-hooks",
        source_home / ".shared-hooks",
        source_home / ".claude/hooks",
        source_home / ".codex/hooks",
    )
    mappings: dict[str, str] = {}
    for hook in catalog.get("agentHooks", []):
        raw_source = hook.get("source")
        if not raw_source:
            continue
        source = Path(os.path.expandvars(raw_source)).expanduser()
        if not source.is_absolute():
            source = source_root / source
        if any(source.is_relative_to(managed) for managed in managed_roots):
            continue
        if not source.is_file():
            raise RuntimeError(
                f"External hook source is missing: {source}\n"
                f"  declared as: {raw_source}\n"
                f"  resolved against source root: {source_root}\n"
                "Pass --source-root <checkout> if that is the wrong checkout, or "
                "run tama-reconcile-registry-sources on the registry if the source moved."
            )
        if source.parent.name == "hooks" and source.parent.parent.name == "scripts":
            external_root = source.parent.parent
            destination = root / "external-hooks" / external_root.parent.name / "scripts"
            for directory_name in ("hooks", "lib"):
                directory = external_root / directory_name
                if directory.is_dir():
                    shutil.copytree(
                        directory,
                        destination / directory_name,
                        dirs_exist_ok=True,
                    )
            mappings[str(external_root)] = str(destination.relative_to(root))
        else:
            destination = root / "external-hooks" / hook["id"] / source.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            # Keyed by the value the registry declares, not by the path it
            # resolved to here: the installer matches this prefix against that
            # declared value, and since the registry became portable the
            # declared value is repository relative while the resolution is
            # this checkout's absolute path.
            mappings[raw_source] = str(destination.relative_to(root))
    (root / "external-sources.json").write_text(
        json.dumps(
            {
                "schema": "ai.wisent.tama.external-hook-sources.v1",
                "mappings": [
                    {"sourcePrefix": source, "releasePath": release}
                    for source, release in sorted(mappings.items())
                ],
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    if root.is_file():
        digest.update(root.read_bytes())
        return digest.hexdigest()
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


def registry_checksum(registry: dict) -> str:
    """The checksum `seal-registry.mjs` and the installer both compute."""
    value = {key: item for key, item in registry.items() if key != "catalogChecksum"}
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode()
    return hashlib.sha256(encoded).hexdigest()


def deployable_sources(value: object, prefix: str) -> object:
    """Every relative `source` restated under `prefix`, at any depth."""
    if isinstance(value, dict):
        result: dict[str, object] = {}
        for key, item in value.items():
            relative = (
                key == "source"
                and isinstance(item, str)
                and bool(item)
                and not item.startswith(("/", "$", "~"))
            )
            result[key] = f"{prefix}/{item}" if relative else deployable_sources(item, prefix)
        return result
    if isinstance(value, list):
        return [deployable_sources(item, prefix) for item in value]
    return value


def state_the_deployable_root(root: Path, source_root: Path) -> str:
    """Restate the release registry's checkout paths with `$HOME`.

    The repository keeps `catalog.maintainedIn` and every `source`
    repository-relative, which is what makes the tracked registry free of one
    operator's machine. `install_hook_release.py` reads that one field twice
    and needs opposite things from it. Its rewrite table takes
    `maintained_in.parent.parent`, so a relative field collapses the root to
    `.` and the table gains the bare token `shared-hooks` — which matches
    inside every `$HOME/.shared-hooks/...` command. Installing release
    9448e04f on 2026-09-08 therefore wrote 39 hook commands as
    `$HOME/./Users/<name>/.shared-hooks/...`: paths that do not exist, so
    those hooks stop running and nothing says so. Its source check wants the
    opposite, a root spelled exactly like the `source` values beside it.

    A release is deployable state rather than a tracked document, so it names
    its checkout with the `$HOME` placeholder both runners already expand, and
    it names sources the same way. The rewrite table then holds
    `$HOME/<checkout>/shared-hooks`, which appears in no command; the `$HOME`
    pair expands commands exactly once; and each source resolves into the
    release tree.
    """
    registry_path = root / "shared-hooks/registry.json"
    registry = json.loads(registry_path.read_text())
    home = Path.home()
    checkout = source_root.resolve()
    if checkout == home or home not in checkout.parents:
        prefix = checkout.as_posix()
    else:
        prefix = f"$HOME/{checkout.relative_to(home).as_posix()}"
    registry = deployable_sources(registry, prefix)
    registry.setdefault("catalog", {})["maintainedIn"] = f"{prefix}/shared-hooks/registry.json"
    registry["catalogChecksum"] = registry_checksum(registry)
    registry_path.write_text(json.dumps(registry, indent=2) + "\n")
    return prefix


def main() -> int:
    if "--digest-file" in sys.argv:
        artifact = Path(next(reversed(sys.argv))).resolve()
        if not artifact.is_file():
            raise SystemExit(f"artifact not found: {artifact}")
        print(tree_digest(artifact))
        return len(())
    arguments = sys.argv[1:]
    source_root = Path.cwd()
    if "--source-root" in arguments:
        index = arguments.index("--source-root")
        if index + 1 >= len(arguments):
            raise SystemExit("--source-root needs a path")
        source_root = Path(arguments[index + 1]).resolve()
        del arguments[index : index + 2]
    if len(arguments) != 1:
        raise SystemExit(
            "usage: seal_hook_release.py [--source-root <checkout>] <release-root>"
        )
    root = Path(arguments[0]).resolve()
    prune_ignored(root)
    package = json.loads((root / "package.json").read_text())
    # The registry is restated first, so the external source manifest is keyed
    # by the same spelling the installer reads back out of it.
    state_the_deployable_root(root, source_root)
    registry = json.loads((root / "shared-hooks/registry.json").read_text())
    package_external_sources(root, registry, source_root)
    prune_ignored(root)
    catalog = registry.get("catalog", {})
    release = {
        "schema": "ai.wisent.tama.hook-release.v1",
        "releaseId": tree_digest(root),
        "packageVersion": package.get("version", "unknown"),
        "catalogVersion": catalog.get("version", "unknown"),
        "catalogUpdatedAt": catalog.get("updatedAt"),
        "sourceDirty": os.environ.get("TAMA_HOOK_SOURCE_DIRTY", "true") == "true",
        "sourceRevision": os.environ.get("TAMA_HOOK_SOURCE_REVISION", "unknown"),
        "sealedAt": datetime.now(timezone.utc).isoformat(),
    }
    (root / "release.json").write_text(json.dumps(release, indent=2, sort_keys=True) + "\n")
    print(release["releaseId"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
