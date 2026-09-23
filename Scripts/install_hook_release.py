#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys


import sys as _size_split_sys
from pathlib import Path as _SizeSplitPath
_size_split_bytecode = _size_split_sys.dont_write_bytecode
_size_split_sys.dont_write_bytecode = True
if str(_SizeSplitPath(__file__).resolve().parent) not in _size_split_sys.path:
    _size_split_sys.path.insert(0, str(_SizeSplitPath(__file__).resolve().parent))
from install_hook_release_parts.schema.schema import SCHEMA, INSTALLED_SCHEMA, NATIVE_MANIFEST_SCHEMA, MINIMUM_NODE_MAJOR, NODE_VERSION_PROBE_TIMEOUT_SECONDS, EXECUTABLE_MODE_BITS, atomic_json, registry_checksum, tree_digest, load_json, transformed, source_candidate, release_file_map, base_config, provider_hook_block, dispatcher_body, supervisor_launcher_body, global_hooks_path  # noqa: F401
from install_hook_release_parts.schema.transaction import Transaction, require_supported_node, pin_node_commands, command_arguments, native_command_names, declared_native_binaries, pin_native_commands, MANAGED_DISPATCHER_MARKER, entrypoint_kind  # noqa: F401
from install_hook_release_parts.schema.verified_release import verified_release, require_approved_sources, installed_registry, copied_release, provider_writes, refuse_entrypoint_conflicts, source_file_changes  # noqa: F401
from install_hook_release_parts.schema.add_git_hook_writes import add_git_hook_writes, register_omp_adapter, apply_install  # noqa: F401
from install_hook_release_parts.install_release.install_release import install_release, main  # noqa: F401
_size_split_sys.dont_write_bytecode = _size_split_bytecode
del _size_split_sys, _SizeSplitPath, _size_split_bytecode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Tama hook release installation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
