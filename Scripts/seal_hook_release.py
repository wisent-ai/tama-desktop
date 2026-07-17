#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import shutil


def prune_ignored(root: Path) -> None:
    for directory in sorted(root.rglob("__pycache__"), reverse=True):
        if directory.is_dir():
            shutil.rmtree(directory)
    for path in root.rglob("*.pyc"):
        path.unlink(missing_ok=True)


def package_external_sources(root: Path, registry: dict) -> None:
    catalog = registry.get("catalog", {})
    maintained_in = Path(catalog.get("maintainedIn", ""))
    codex_path = Path(registry.get("adapters", {}).get("codex", {}).get("path", ""))
    source_root = maintained_in.parent.parent
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
        source = Path(raw_source)
        if any(source.is_relative_to(managed) for managed in managed_roots):
            continue
        if not source.is_file():
            raise RuntimeError(f"External hook source is missing: {source}")
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
            mappings[str(external_root)] = str(
                destination.relative_to(root)
            )
        else:
            destination = root / "external-hooks" / hook["id"] / source.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            mappings[str(source)] = str(destination.relative_to(root))
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


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: seal_hook_release.py <release-root>")
    root = Path(sys.argv[1]).resolve()
    prune_ignored(root)
    package = json.loads((root / "package.json").read_text())
    registry = json.loads((root / "shared-hooks/registry.json").read_text())
    package_external_sources(root, registry)
    prune_ignored(root)
    catalog = registry.get("catalog", {})
    release = {
        "schema": "ai.wisent.tama.hook-release.v1",
        "releaseId": tree_digest(root),
        "packageVersion": package.get("version", "unknown"),
        "catalogVersion": catalog.get("version", "unknown"),
        "catalogUpdatedAt": catalog.get("updatedAt"),
        "sealedAt": datetime.now(timezone.utc).isoformat(),
    }
    (root / "release.json").write_text(json.dumps(release, indent=2, sort_keys=True) + "\n")
    print(release["releaseId"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
