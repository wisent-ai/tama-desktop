# Scripts reference

Every executable under `Scripts/`, with its arguments, environment, output,
and exit behavior. Three of them ship inside the app bundle and run on
operator machines (`install_hook_release.py`, `emergency_disable_hooks`, and
the sealed release they act on); the rest are maintainer tools that run only
in a checkout. The sealed CLI itself is documented in [cli](cli.md); the
integrity model these scripts implement is [concepts/seal](concepts/seal.md).

## Bundled on operator machines

### install_hook_release.py

The transactional installer. The desktop bundles it at
`Tama.app/Contents/Resources/install_hook_release.py` and runs it for every
runtime install; `emergency_disable_hooks` runs it for session controllers
and re-enable. Wire format: one JSON result object on stdout on success; on
any failure, one line on stderr —
`Tama hook release installation failed: <reason>` — and exit `1`.

```
install_hook_release.py --release <dir> --home <dir>
                        [--emergency-manifest <file>] [--session-control-only]
```

| Argument | Meaning |
|---|---|
| `--release` (required) | The sealed release root to install; must contain `release.json` with schema `ai.wisent.tama.hook-release.v1` |
| `--home` (required) | The target home directory; every managed write resolves against it |
| `--emergency-manifest` | The `emergency-backup/manifest.json` written by a global disable; restores every entrypoint it names |
| `--session-control-only` | Install hook sources and provider session controllers without Git dispatchers or entrypoint restoration |

Without `--session-control-only`, `--emergency-manifest` is required: the
refusal is `Full hook installation requires an emergency manifest`. The full
gate order and write set are in [hook-releases](hook-releases.md); every
refusal sentence is in the [runbook](runbook.md). Environment: `TAMA_OMP`
overrides the `omp` executable used to register the OMP adapter.

The success object has keys `installed` (the new `installed.json` content),
`previous`, `managedSourceFiles`, `restoredEntrypoints`, and
`sessionControlOnly`.

### emergency_disable_hooks

The global kill switch, bundled at
`Tama.app/Contents/Resources/emergency_disable_hooks`. No positional
arguments; everything is environment:

| Variable | Default | Effect |
|---|---|---|
| `TAMA_EMERGENCY_ACTION` | `disable` | `disable` or `enable`; anything else prints `Unsupported Tama emergency action: <value>` and exits `2` |
| `TAMA_HOME` | `$HOME` | Target home |
| `TAMA_SKIP_SESSION_RESTART` | `0` | `1` skips the supervised-session pause/resume |
| `TAMA_HOOK_RELEASE_ROOT` | bundled `hooks-release` (falls back to `.build/Tama.app/...` in a checkout) | Release root |
| `TAMA_HOOK_INSTALLER` | sibling `install_hook_release.py` | Installer override |
| `TAMA_SESSION_SUPERVISOR` | `$TAMA_HOOK_RELEASE_ROOT/shared-hooks/agent-session-supervisor.py` | Supervisor override; if missing (and sessions are not skipped) the script prints `Tama session supervisor is missing: <path>` and exits `66` |

Disable ends with `Disabled hooks. Supervised agent sessions will resume
without an editor restart.`; a repeat prints `Tama hooks are already
disabled.` and exits `0`. Enable ends with `Enabled approved hook release
<first-12-of-id>. Supervised agent sessions will resume without an editor
restart.`; enable without a manifest fails with `Tama has no emergency backup
manifest to restore.`. The step-by-step behavior is in
[enforcement-control](enforcement-control.md) and
[concepts/emergency-disable](concepts/emergency-disable.md).

## Read-only integrity reporters

All three reuse the installer's own `tree_digest`, so what they verify is by
construction what the installer enforces. All are read-only and documented
end-to-end in [walkthrough-verify-release](walkthrough-verify-release.md)
and [walkthrough-runtime-status](walkthrough-runtime-status.md); runnable
wrappers live in [`../examples/integrity/`](../examples/integrity/).

### verify_hook_release.py

```
verify_hook_release.py [release-root]
```

Default root: `.build/Tama.app/Contents/Resources/hooks-release` relative to
the checkout. Prints `release root:`, `recorded releaseId:`, `actual tree
digest:`, `sealed at:`, `source dirty:`, then `result: intact` or
`result: DRIFTED` followed by `written after the seal:` and one
timestamp-plus-path line per file newer than `sealedAt`. When nothing is
newer, it prints `no file is newer than the seal -- the drift is a permission
change, a deletion, or a file whose timestamp was preserved on copy.` A
missing root prints `absent -- nothing to verify`. Exit is always `0` — the
verdict is the text, not the status.

### verify_installed_releases.py

```
verify_installed_releases.py
```

No arguments; `TAMA_HOME` selects the home, `TAMA_HOOK_RELEASE_ROOT` the
bundled release to check the second gate against. Digests every tree under
`hooks-runtime/releases/` against its directory name (`intact` /
`DRIFTED`, with ` <- current` on the live one), then answers which of the two
identically worded installer failures an emergency enable would hit: `second
gate: install would copy a fresh tree, so it cannot fail` or `second gate:
DRIFTED -- install would refuse`. With no releases directory it prints
`nothing installed`. Exit `0`.

### report_hook_release_integrity.py

```
report_hook_release_integrity.py [release-root]
```

Default root: a sibling `hooks-release` (when bundled), else the checkout's
`.build` release. Prints `root:`, `sealed:`, `actual:`, and `verdict: intact`
or `verdict: MISMATCH`; on mismatch it additionally lists `covered by the
digest but never installed:` (build residue such as `.pyc` files and the
pruned generator files) and `written after sealedAt <time>:`. A missing
manifest prints `no release manifest at <path>` and exits `1`; otherwise exit
`0`.

## Build and release (maintainer-only)

### build-app.sh

Builds, signs, and installs the app bundle from a checkout: Swift release
build, the two system-policy binaries and the Network Extension, the sealed
Rust `tama-cli` and `tama-mcp-server` (built with `cargo` from the hook
source tree's `rust/` workspace), the catalog snapshot
(`export-catalog.mjs`), the staged hook release sealed by
`seal_hook_release.py`, and `tama-build.json`. No arguments; the environment
variables (`TAMA_HOOK_ROOT`, `TAMA_RELEASE_VERSION`, `TAMA_BUILD_CHANNEL`,
`WISENT_CODESIGN_IDENTITY`, provisioning profiles, `TAMA_NODE`,
`TAMA_CARGO`, `TAMA_INSTALL_APP_PATH`, `TAMA_INSTALL_AFTER_BUILD`,
`WISENT_RESTART_AFTER_BUILD`, …) are tabled in
[operations](operations.md#configuration). It requires Node.js 20+, a
resolvable codesigning identity, and a Git checkout for both the desktop and
hook source trees. Output ends with `Built <path>` and, unless
`TAMA_INSTALL_AFTER_BUILD=no`, `Installed <path>`.

### seal_hook_release.py

```
seal_hook_release.py <release-root>
seal_hook_release.py --digest-file <artifact>
```

First form: prunes `__pycache__`/`.pyc`, packages external hook sources into
`external-hooks/` with an `external-sources.json` mapping (schema
`ai.wisent.tama.external-hook-sources.v1`, refusing when an external source
is missing: `External hook source is missing: <path>`), computes the tree
digest, and writes `release.json` with the digest as `releaseId`; prints the
id. `TAMA_HOOK_SOURCE_DIRTY` and `TAMA_HOOK_SOURCE_REVISION` populate
provenance. Second form: prints the SHA-256 of one file (used for artifact
`.digest` sidecars); a missing file exits with `artifact not found: <path>`.
Wrong usage exits with `usage: seal_hook_release.py <release-root>`. The
digest definition is in [concepts/seal](concepts/seal.md).

### export-catalog.mjs

```
export-catalog.mjs <tama-root> <output-path>
```

Renders the desktop's catalog snapshot by running the Rust CLI
(`tama-cli list --root <tama-root> --json`; override the binary with
`TAMA_CLI`) and normalizing defaults (`category` → `Uncategorized`, `status`
→ `unknown`, missing event `timeout` → `0`). Missing arguments throw
`usage: export-catalog.mjs <tama-root> <output-path>`.

### stage_live_hook_release.py

No arguments. Copies the installed runtime (`hooks-runtime/current`) to
`.work/inline-hook-release`, strips its `release.json`, and replaces
`shared-hooks/` with the tree from `TAMA_HOOK_SOURCE_ROOT` (default: the
`tama` checkout beside this repository); prints the staged path. A developer
seam for iterating on hook sources against a real runtime layout.

### package-release.sh

No arguments. Packages the immutable release candidate for the exact signed
`v<SemVer>` tag at `HEAD` (`TAMA_RELEASE_TAG` disambiguates). It refuses,
each with its own printed sentence, on: a missing `Package.resolved`,
multiple release tags at `HEAD`, a tag that is not `v<SemVer>`, invalid
SemVer, a dirty desktop or hook checkout, a tag that does not resolve to
`HEAD`, a missing or still-`Unreleased` `CHANGELOG.md` section, missing
signing/provisioning/notary variables, dirty build provenance, mismatched
component versions, and any pre-existing artifact output (`Refusing to
overwrite immutable release output: <path>`). It then builds with
`--timestamp` signing, notarizes and staples, and writes
`Tama-<version>-macOS-<arch>.zip` plus `.digest` and `.provenance.json`
(schema `ai.wisent.tama.release-provenance`) under
`.build/releases/<version>/`. Channels: a pre-release version packages as
`preview`, otherwise `stable`. Details: [releases](releases.md).

### publish-release.sh

No arguments; same tag resolution as packaging (`Publication requires the
exact signed v<SemVer> release tag at HEAD.`). Verifies the packaged
artifact, digest, provenance, and qualification sidecars for that version and
publishes them to the immutable GitHub release; a pre-release version
publishes as a GitHub prerelease and never becomes `latest`. The publication
contract is in [releases](releases.md#release-process).

### import-brand-icon.sh

```
import-brand-icon.sh PRODUCT OUTPUT.icns
```

Fetches the canonical app icon from the asset resolver named by
`WISENT_GROUND_TRUTH_API` (unset: `WISENT_GROUND_TRUTH_API must point to the
canonical asset resolver.`, exit `64`), renders the iconset with `sips`, and
writes the `.icns`. Requires `curl`, `sips`, `iconutil` (missing tool: exit
`69`).

### wisent-restart-app

```
wisent-restart-app [--if-running] [--timeout SECONDS] APP.app
```

Terminates the running app identified by the bundle's
`CFBundleIdentifier` through LaunchServices, waits up to `--timeout` (default
15 s), and relaunches the supplied bundle in the background. `--if-running`
skips a stopped app (`Not running; skipped <bundle> (<id>)`). Exit codes:
`64` usage, `66` missing bundle or `Info.plist`, `65` empty bundle id, `75`
termination or launch timeout. Success prints `Restarted <bundle> (<id>)`.
`build-app.sh` runs it automatically after installing a development build.
