# Seal and integrity

What makes a Tama hook release tamper-evident, and which checks actually
stand between a modified tree and a running session? One digest definition,
computed in one place, enforced at three moments.

## What it is

The seal is a SHA-256 digest over every file in the release tree except
`release.json`, in sorted path order. Per file, three length-framed values
enter the hash: the relative POSIX path, the permission bits
(`mode & 0o777`, 4 bytes big-endian), and the raw bytes. The definition
lives in exactly two places that must agree by construction:
`Scripts/seal_hook_release.py::tree_digest` (writer) and
`install_hook_release.py::tree_digest` (enforcer); the three read-only
reporters import the installer's copy rather than restating the rule
([scripts](../scripts.md#read-only-integrity-reporters)).

Consequences that follow directly from the definition:

- a one-byte rewrite changes the identity
  ([walkthrough](../walkthrough-verify-release.md#3-drift-one-byte-and-catch-it));
- a `chmod` with identical bytes changes the identity
  ([walkthrough](../walkthrough-verify-release.md#4-drift-a-permission-bit-and-catch-that-too));
- adding or deleting any file changes the identity;
- editing `release.json` itself does not — the manifest is the claim, the
  tree is the evidence.

## Who declares it

`Scripts/seal_hook_release.py`, run once by `Scripts/build-app.sh` after the
release tree is staged and pruned. The digest becomes `releaseId` in
`release.json` (schema `ai.wisent.tama.hook-release.v1`), beside
`packageVersion`, `catalogVersion`, `catalogUpdatedAt`, `sourceDirty`,
`sourceRevision`, and `sealedAt`. Sealing is the last write: anything that
touches the tree afterwards is drift, which is why the build prunes Python
bytecode and generator files *before* sealing
([hook-releases](../hook-releases.md#sealing)).

## Who enforces it

Three gates, all inside `install_hook_release.py`:

| Moment | Check | Refusal |
|---|---|---|
| Before any write | Bundled tree digests to its recorded `releaseId` | `Bundled Tama hook release failed its integrity check` |
| After content-addressed copy | `releases/<id>` digests to `<id>`; a stale pre-existing copy is deleted and recopied first | `Installed Tama hook release failed its integrity check` |
| Before the manifest is trusted | `release.json` schema equals `ai.wisent.tama.hook-release.v1` | `Unsupported Tama hook release manifest` |

Both integrity refusals surface verbatim wherever the installer runs: the
desktop's runtime install, the emergency disable's session-controller
reinstall, and the emergency re-enable
([runbook](../runbook.md#bundled-tama-hook-release-failed-its-integrity-check)).

## Who reports it

The refusals are deliberately terse — they name no file. Attribution is the
job of the read-only reporters:
`verify_hook_release.py` (recorded vs actual digest, files written after
`sealedAt`), `report_hook_release_integrity.py` (adds the
covered-but-never-installed residue list), and
`verify_installed_releases.py` (every installed tree against its directory
name, plus which of the two identically worded failures an emergency enable
would hit). All three executed with real output in
[walkthrough-verify-release](../walkthrough-verify-release.md) and
[walkthrough-runtime-status](../walkthrough-runtime-status.md).

## Where it lives

| Location | Role |
|---|---|
| `<release>/release.json` → `releaseId` | The sealed claim |
| `Tama.app/Contents/Resources/tama-build.json` → `hookRelease` | The same object embedded in build provenance, so the app displays its bundled identity without reopening the release |
| `hooks-runtime/releases/<release-id>/` | Content-addressed installed copy: the directory name is the claim |
| `hooks-runtime/installed.json` → `releaseId`, `catalogChecksum` | What the last successful install recorded |
| Session records → `runtime.loadedReleaseId`, `runtime.catalogChecksum` | What each live session actually loaded |

`catalogChecksum` is a second, narrower integrity value: the SHA-256 of the
rewritten registry JSON with the checksum field removed, recomputed by the
installer after path rewriting — it travels into every session record so the
desktop compares catalogs by checksum rather than by trust
([concepts/registry](registry.md)).

## Not to be confused with

- **Code signing.** The macOS signature authenticates the app bundle and its
  binaries; the seal authenticates the *hook tree* independently of Apple's
  formats, including after it is copied out of the bundle into
  `hooks-runtime/`. A release passes both or it does not install.
- **The artifact digest.** `Tama-<version>-macOS-<arch>.zip.digest` is the
  SHA-256 of the distribution zip ([releases](../releases.md#release-artifact));
  the seal is the identity of the hook tree inside it. `seal_hook_release.py
  --digest-file` computes the former with the same tool, but they answer
  different questions.
- **The product version.** Versions are claims in mutable metadata; the seal
  is content. Two trees with the same `packageVersion` and one changed bit
  have different `releaseId`s ([releases](../releases.md#product-and-hook-identities)).
