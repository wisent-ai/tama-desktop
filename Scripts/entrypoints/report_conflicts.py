#!/usr/bin/env python3
"""Report every hook entrypoint an emergency re-enable cannot restore.

`install_hook_release.py` refuses when both an entrypoint and its
`.tama-disabled` sibling exist, because it cannot know which one the operator
wants. It reports the first such pair and stops, so an operator restoring
policy learns about them one failed run at a time. This reads the emergency
manifest and reports all of them at once, plus whether each active file is a
Tama-managed dispatcher (which the installer would rewrite anyway) or
something else (which a person has to decide about).

Read-only. It writes nothing and moves nothing.

Usage:
  report_conflicts.py [--home HOME] [--json]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

MANAGED_MARKER = "tama managed"
SUFFIX = ".tama-disabled"


def manifest_path(home: Path) -> Path:
    return home / "Library/Application Support/Tama/emergency-backup/manifest.json"


def moved_pairs(manifest: dict) -> list[tuple[Path, Path]]:
    """Every (active, disabled) pair the bypass recorded.

    The manifest's `moved` entries are pairs; older manifests recorded them as
    objects and newer ones as two-element lists, so both shapes are read
    rather than assumed.
    """
    pairs: list[tuple[Path, Path]] = []
    for entry in manifest.get("moved") or []:
        if isinstance(entry, dict):
            source = entry.get("from") or entry.get("source") or entry.get("path")
            target = entry.get("to") or entry.get("target") or entry.get("disabled")
        elif isinstance(entry, (list, tuple)) and len(entry) == 2:
            source, target = entry
        else:
            continue
        if not source or not target:
            continue
        active, disabled = Path(str(source)), Path(str(target))
        if disabled.name.endswith(SUFFIX):
            pairs.append((active, disabled))
        elif active.name.endswith(SUFFIX):
            pairs.append((disabled, active))
    return pairs


def classify(active: Path) -> str:
    """What the active file is, in the terms an operator has to decide in."""
    try:
        head = active.read_text(errors="replace")[:400]
    except OSError as error:
        return f"unreadable: {error}"
    return "tama-managed dispatcher" if MANAGED_MARKER in head else "not Tama-managed"


def conflicts(home: Path) -> list[dict[str, str]]:
    path = manifest_path(home)
    if not path.is_file():
        raise SystemExit(f"no emergency backup manifest at {path}")
    manifest = json.loads(path.read_text())
    found = []
    for active, disabled in moved_pairs(manifest):
        if active.exists() and disabled.exists():
            found.append(
                {
                    "active": str(active),
                    "disabled": str(disabled),
                    "activeKind": classify(active),
                }
            )
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    found = conflicts(args.home.resolve())
    if args.json:
        print(json.dumps({"conflicts": found}, indent=2, sort_keys=True))
    elif not found:
        print("no conflicting hook entrypoints; a re-enable can restore every moved file")
    else:
        print(f"{len(found)} conflicting hook entrypoint(s):")
        for entry in found:
            print(f"  {entry['active']}")
            print(f"    active file: {entry['activeKind']}")
            print(f"    disabled copy: {entry['disabled']}")
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main())
