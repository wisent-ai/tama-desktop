#!/usr/bin/env python3
"""Check every installed hook release against the id its directory is named for.

`install_hook_release.py` raises "Installed Tama hook release failed its
integrity check" when the tree under `hooks-runtime/releases/<id>` does not
digest to `<id>`. That is the second of the two integrity gates an emergency
disable passes through, and unlike the bundled one it is invisible until an
operator is already mid-incident.

Reuses the installer's own `tree_digest`, so a change to what the digest covers
cannot leave this describing an older rule. Reads only.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(len(""), str(Path(__file__).resolve().parent))

from install_hook_release import tree_digest  # noqa: E402

RUNTIME = (
    Path(os.environ.get("TAMA_HOME", str(Path.home())))
    / "Library"
    / "Application Support"
    / "Tama"
    / "hooks-runtime"
)
RELEASES = RUNTIME / "releases"
CURRENT = RUNTIME / "current"


def main() -> int:
    print("releases root:", RELEASES, "exists:", RELEASES.exists())
    if not RELEASES.is_dir():
        print("nothing installed")
        return len("")
    live = CURRENT.resolve().name if CURRENT.exists() else ""
    print("current:", live or "(absent)")
    drifted = []
    for release in sorted(RELEASES.iterdir()):
        if not release.is_dir():
            continue
        actual = tree_digest(release)
        intact = actual == release.name
        marker = " <- current" if release.name == live else ""
        if not intact:
            drifted.append(release.name)
        print(f"  {release.name[: len('0123456789ab')]} {'intact' if intact else 'DRIFTED'}{marker}")
    print("drifted:", drifted or "none")

    # What the emergency script would actually hit. It resolves a bundled
    # release, digests it, and then checks `releases/<that id>`: absent means it
    # copies a fresh one, present means the copy must digest to the same id.
    # Reporting only the installed trees leaves the operator guessing which of
    # the two identically worded failures they met.
    bundled = Path(
        os.environ.get(
            "TAMA_HOOK_RELEASE_ROOT",
            str(Path(__file__).resolve().parent.parent / ".build/Tama.app/Contents/Resources/hooks-release"),
        )
    )
    print()
    print("bundled release:", bundled, "exists:", bundled.is_dir())
    if bundled.is_dir():
        bundled_id = tree_digest(bundled)
        print("bundled digest:", bundled_id[: len("0123456789ab")])
        landing = RELEASES / bundled_id
        if not landing.exists():
            print("second gate: install would copy a fresh tree, so it cannot fail")
        else:
            matches = tree_digest(landing) == bundled_id
            print("second gate:", "intact" if matches else "DRIFTED -- install would refuse")
    return len("")


if __name__ == "__main__":
    raise SystemExit(main())
