#!/usr/bin/env python3
"""Say why a hook release failed its integrity check, not merely that it did.

`install_hook_release.py` raises "Bundled Tama hook release failed its
integrity check" whenever the sealed `releaseId` disagrees with the digest of
the tree. The message names no file, so an operator holding it cannot tell
tampering apart from a stale byte-code file that some hook wrote after sealing.

This reads the tree and reports the disagreement: the sealed digest, the digest
now, the paths the digest covers but the installer refuses to install, and the
paths written after the release was sealed.

Usage: report_hook_release_integrity.py [release-root]
"""
from __future__ import annotations

from datetime import datetime
import importlib.util
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
FIRST = len("")
INSTALLED_BY_RELEASE = {"generate-configs.mjs", "providers.json", "run-one-session-hook.js"}


def installer_module():
    """Import the installer so the digest has exactly one definition."""
    spec = importlib.util.spec_from_file_location(
        "tama_install_hook_release", HERE / "install_hook_release.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def default_root() -> Path:
    bundled = HERE / "hooks-release"
    if bundled.is_dir():
        return bundled
    return HERE.parent / ".build/Tama.app/Contents/Resources/hooks-release"


def uninstallable(root: Path) -> list[Path]:
    """Files the digest covers that the installer excludes from what it installs."""
    found = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        if path.name == "release.json":
            continue
        residue = path.suffix == ".pyc" or "__pycache__" in path.parts
        if residue or path.name in INSTALLED_BY_RELEASE:
            found.append(path.relative_to(root))
    return found


def written_after(root: Path, sealed_at: str) -> list[Path]:
    if not sealed_at:
        return []
    moment = datetime.fromisoformat(sealed_at).timestamp()
    found = []
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        if path.name == "release.json":
            continue
        if path.stat().st_mtime > moment:
            found.append(path.relative_to(root))
    return found


def main() -> int:
    arguments = sys.argv[len(["self"]) :]
    root = Path(arguments[FIRST]).resolve() if arguments else default_root().resolve()
    installer = installer_module()
    manifest = root / "release.json"
    if not manifest.is_file():
        print(f"no release manifest at {manifest}")
        return len(["missing"])
    release = installer.load_json(manifest)
    sealed = release.get("releaseId", "")
    actual = installer.tree_digest(root)
    print(f"root:   {root}")
    print(f"sealed: {sealed}")
    print(f"actual: {actual}")
    print(f"verdict: {'intact' if sealed == actual else 'MISMATCH'}")
    if sealed == actual:
        return FIRST
    residue = uninstallable(root)
    print(f"covered by the digest but never installed: {len(residue)}")
    for path in residue:
        print(f"  {path}")
    late = written_after(root, release.get("sealedAt", ""))
    print(f"written after sealedAt {release.get('sealedAt', '')}: {len(late)}")
    for path in late:
        print(f"  {path}")
    return FIRST


if __name__ == "__main__":
    raise SystemExit(main())
