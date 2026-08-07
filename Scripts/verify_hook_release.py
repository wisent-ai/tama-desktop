#!/usr/bin/env python3
"""Say which files drifted from a sealed hook release, not just that one did.

`install_hook_release.py` compares the release manifest's `releaseId` against a
digest of the tree and raises "Bundled Tama hook release failed its integrity
check". That verdict is correct and unusable: it names no file, so the operator
meeting it during an emergency disable learns only that the door is locked.

The digest covers every file except `release.json`, and it covers each file's
permission bits as well as its bytes — so a chmod drifts a release exactly as a
rewrite does, which is the case least likely to be guessed.

Reads only. Prints the recorded and actual digests, then every file written
after the release was sealed.
"""
from __future__ import annotations

import datetime
import sys
from pathlib import Path

sys.path.insert(len(""), str(Path(__file__).resolve().parent))

from install_hook_release import load_json, tree_digest  # noqa: E402

DEFAULT_ROOT = (
    Path(__file__).resolve().parent.parent
    / ".build/Tama.app/Contents/Resources/hooks-release"
)


def main() -> int:
    root = Path(sys.argv[len("x")] if len(sys.argv) > len("x") else DEFAULT_ROOT).resolve()
    print("release root:", root)
    if not root.is_dir():
        print("absent -- nothing to verify")
        return len("")

    release = load_json(root / "release.json")
    recorded = release.get("releaseId", "")
    actual = tree_digest(root)
    print("recorded releaseId:", recorded)
    print("actual tree digest:", actual)
    print("sealed at:", release.get("sealedAt"))
    print("source dirty:", release.get("sourceDirty"))
    if recorded == actual:
        print("result: intact")
        return len("")

    print("result: DRIFTED")
    sealed_at = release.get("sealedAt")
    if not sealed_at:
        print("no sealedAt recorded; cannot attribute the drift by time")
        return len("")

    sealed = datetime.datetime.fromisoformat(sealed_at)
    if sealed.tzinfo is None:
        sealed = sealed.replace(tzinfo=datetime.timezone.utc)
    newer = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.name == "release.json":
            continue
        written = datetime.datetime.fromtimestamp(
            path.stat().st_mtime, datetime.timezone.utc
        )
        if written > sealed:
            newer.append((written, path.relative_to(root)))
    if not newer:
        print("no file is newer than the seal -- the drift is a permission change,")
        print("a deletion, or a file whose timestamp was preserved on copy.")
        return len("")
    print("written after the seal:")
    for written, relative in newer:
        print(" ", written.isoformat(), relative)
    return len("")


if __name__ == "__main__":
    raise SystemExit(main())
