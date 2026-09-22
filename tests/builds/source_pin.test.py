"""Exercise the real source producer and native packager's identity contract."""

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

PROJECT = Path(__file__).resolve().parents[2]
PRODUCER = PROJECT / "Scripts/hook_source/__main__.py"
CONSUMER = PROJECT / "Scripts/hook_release_native/source.py"


class SourceArchiveJourney(unittest.TestCase):
    def test_verified_archive_survives_packaging_but_changed_inputs_are_refused(self):
        evidence = PROJECT / ".build/source-proof" / str(uuid.uuid4())
        evidence.mkdir(parents=True)
        commands = []
        passed = False

        def run(*arguments):
            result = subprocess.run(arguments, cwd=PROJECT, text=True, capture_output=True)
            commands.append({"argv": arguments, "exit_status": result.returncode,
                             "stdout": result.stdout, "stderr": result.stderr})
            (evidence / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
            return result

        def success(*arguments):
            result = run(*arguments)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            return result.stdout.strip()

        revision = success("git", "rev-parse", "HEAD")
        (evidence / "source.patch").write_text(success("git", "diff", "--binary", "HEAD"))
        (evidence / "source.json").write_text(json.dumps({
            "revision": revision,
            "tools": {str(path.relative_to(PROJECT)): hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in (PRODUCER, CONSUMER, Path(__file__))},
        }, indent=2) + "\n")
        print(f"Source archive evidence: {evidence}")
        try:
            archive = Path(success(sys.executable, str(PRODUCER), "verify"))
            pinned_revision = (PROJECT / "Release/tama-revision").read_text().strip()
            (evidence / "archive.json").write_text(json.dumps({
                "path": str(archive), "revision": pinned_revision,
                "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            }, indent=2) + "\n")
            with tempfile.TemporaryDirectory(prefix="inputs-", dir=evidence) as temporary:
                root = Path(success(sys.executable, str(PRODUCER), "unpack", "--destination", temporary))
                identity = json.loads(success(sys.executable, str(CONSUMER), "--source-root", str(root)))
                self.assertEqual(identity["revision"], pinned_revision)
                self.assertFalse(identity["dirty"])
                self.assertFalse((root / ".git").exists())
                package = root / "package.json"
                original = package.read_bytes()
                refused = run(sys.executable, str(PRODUCER), "unpack", "--destination", temporary)
                self.assertNotEqual(refused.returncode, 0)
                self.assertEqual(package.read_bytes(), original)
                package.write_bytes(original + b"\n")
                self.assertNotEqual(run(sys.executable, str(CONSUMER), "--source-root", str(root)).returncode, 0)
                package.write_bytes(original)
                additional = root / "rust/approval-proof-extra.rs"
                additional.write_text("pub const UNCOMMITTED: bool = true;\n")
                self.assertNotEqual(run(sys.executable, str(CONSUMER), "--source-root", str(root)).returncode, 0)
                additional.unlink()
                package.unlink()
                self.assertNotEqual(run(sys.executable, str(CONSUMER), "--source-root", str(root)).returncode, 0)
                package.write_bytes(original)
                marker = root / ".tama-source-archive.json"
                original_marker = marker.read_text()
                wrong_origin = json.loads(original_marker)
                wrong_origin["revision"] = "0" * 40
                marker.write_text(json.dumps(wrong_origin))
                self.assertNotEqual(run(sys.executable, str(CONSUMER), "--source-root", str(root)).returncode, 0)
                marker.write_text(original_marker)
                final = json.loads(success(sys.executable, str(CONSUMER), "--source-root", str(root)))
                self.assertEqual(final, identity)
            passed = True
        finally:
            (evidence / "result.json").write_text(json.dumps({"passed": passed}) + "\n")


if __name__ == "__main__":
    unittest.main()
