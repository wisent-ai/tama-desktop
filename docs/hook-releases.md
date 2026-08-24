# Hook releases

How does an approved hook tree become the runtime a session loads, and how
does Tama know nobody changed it in between? Through one identity: a hook
release is a directory whose name and manifest are the SHA-256 digest of its
own contents, checked when it is sealed, checked before it is installed, and
checked again after it lands. Hook policy evolves separately from the
desktop app, so the two have separate identities — the product version
policy is in [releases](releases.md).

## The release tree

`Scripts/build-app.sh` stages the release into
`Tama.app/Contents/Resources/hooks-release` from the hook source tree
selected by `TAMA_HOOK_ROOT`:

| Member | Content |
|---|---|
| `release.json` | The seal manifest (below) |
| `shared-hooks/` | The registry, hook scripts, session supervisor, universal runtime, OMP adapter, Node preflight |
| `claude-hooks/`, `codex-hooks/` | Provider-specific hook entrypoints |
| `repo-githooks/<project>/` | Approved per-repository Git hooks |
| `external-hooks/` + `external-sources.json` | Approved hook sources that live outside the managed roots, packaged in with `sourcePrefix` → `releasePath` mappings (schema `ai.wisent.tama.external-hook-sources.v1`) |
| `bin/tama-cli`, `bin/tama-mcp-server` | The sealed, signed Rust backend and MCP server |
| `package.json` | The hook package version |

Generator files (`generate-configs.mjs`, `providers.json`,
`run-one-session-hook.js`) and Python bytecode are pruned before sealing.

## Sealing

`Scripts/seal_hook_release.py` computes the tree digest: every file except
`release.json`, in sorted path order, hashing each file's relative path, its
permission bits, and its bytes, each length-framed. A `chmod` therefore
drifts a release exactly as a rewrite does. The digest becomes `releaseId`
in `release.json`, schema `ai.wisent.tama.hook-release.v1`, together with
`packageVersion`, `catalogVersion`, `catalogUpdatedAt`, `sourceDirty`,
`sourceRevision` (the hook source Git commit), and `sealedAt`. The build
manifest `tama-build.json` embeds the same object, so the app can display
its bundled hook identity without reopening the release.

## Installation

`Scripts/install_hook_release.py` (bundled in the app resources, run by the
desktop's explicit install action) takes `--release`, `--home`, and either
`--session-control-only` or `--emergency-manifest`. It passes two integrity
gates and refuses at either:

1. **Bundled gate.** The release tree must digest to its recorded
   `releaseId` — otherwise `Bundled Tama hook release failed its integrity
   check`.
2. **Installed gate.** The release is copied content-addressed to
   `~/Library/Application Support/Tama/hooks-runtime/releases/<release-id>`;
   a pre-existing copy that no longer digests to its directory name is
   deleted and recopied, and a copy that still fails afterwards aborts with
   `Installed Tama hook release failed its integrity check`.

Before any managed write it resolves Node.js from `PATH`,
`/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`, requires major
version 20 or newer, canonicalizes the executable through symlinks, and
pins it into every Node-based hook command with
`shared-hooks/node-runtime-preflight.cjs` preloaded. It rewrites every
registry path from the canonical source root and home (identified by the
registry's own `maintainedIn` and adapter paths) to the target home, stamps
the registry with the `releaseId`, and recomputes `catalogChecksum`.

The write set is transactional — every touched file is backed up first and
restored on failure:

- `~/.shared-hooks`, `~/.claude/hooks`, `~/.codex/hooks` — hook sources and
  the rewritten `registry.json`;
- `~/.claude/settings.json`, `~/.codex/hooks.json` — regenerated provider
  configs, mode `0600`;
- `~/.local/bin/tama-agent` — the generated supervisor launcher, exporting
  the pinned Node executable and preflight;
- `pre-commit` and `pre-push` dispatchers at the user-global Git hooks path
  (`git config --global core.hooksPath`, defaulting to
  `~/.config/git/hooks`), each running the repository's own
  `.githooks/<name>`, else the archived per-repository hook from
  `hooks-runtime/current`, then any preserved `<name>.before-tama` backup;
- approved `repo-githooks` into each matching project's `.githooks/`.

The `hooks-runtime/current` symlink is replaced atomically only inside the
transaction; on failure the previous symlink and every original file come
back, and an OMP extensions change (registering
`~/.shared-hooks/omp-shared-hooks.js` via `omp config set extensions`) is
reverted. Obsolete files from the previous install are deleted only when
they sit under the managed roots — anything else aborts the install.

Success writes `hooks-runtime/installed.json`, schema
`ai.wisent.tama.installed-hook-release.v1`: `releaseId`, `catalogChecksum`,
`packageVersion`, `catalogVersion`, `catalogUpdatedAt`, `installedAt`,
`previousReleaseId`, `sourceFiles` (every managed path), `nodeExecutable`,
and `nodeVersion`. That file is what the desktop reads as the installed
identity.

## Verifying a release by hand

Three read-only maintainer scripts answer *which file drifted*, not just
that one did:

- `Scripts/verify_hook_release.py [root]` — recomputes the bundled tree
  digest, prints recorded vs actual, and lists every file written after
  `sealedAt`;
- `Scripts/verify_installed_releases.py` — digests every tree under
  `hooks-runtime/releases/` against its directory name, marks the `current`
  one, and reports which of the two identically worded install failures an
  emergency enable would hit;
- `Scripts/report_hook_release_integrity.py [root]` — on mismatch, also
  lists files the digest covers that the installer never installs (build
  residue such as bytecode).

Never edit files inside a release directory; the recovery for integrity
failure is reinstalling the same verified app artifact
([operations](operations.md)).
