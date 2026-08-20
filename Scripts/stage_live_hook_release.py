#!/usr/bin/env python3
"""Stage a sealed Tama hook release from canonical hook sources."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import sys


def main() -> None:
    home = Path.home()
    project = Path(__file__).resolve().parent.parent
    runtime = home / "Library/Application Support/Tama/hooks-runtime/current"
    source_root = Path(
        os.environ.get("TAMA_HOOK_SOURCE_ROOT") or project.parent / "tama"
    )
    destination = project / ".work/inline-hook-release"
    shutil.rmtree(destination, ignore_errors=True)
    shutil.copytree(runtime, destination, symlinks=True)
    (destination / "release.json").unlink(missing_ok=True)

    shared_destination = destination / "shared-hooks"
    shutil.rmtree(shared_destination)
    shutil.copytree(source_root / "shared-hooks", shared_destination)
    sys.stdout.write(str(destination) + "\n")


if __name__ == "__main__":
    main()
