# Hook release

What exactly is the unit of hook-policy deployment on a machine? A hook
release: an immutable, content-addressed directory tree carrying the
registry, every approved hook source, the sealed Rust backend, and a
manifest whose `releaseId` is the SHA-256 digest of the tree itself. Nothing
smaller deploys — no single hook, no patch — and nothing mutates in place.

## What it is

A directory with this shape ([hook-releases](../hook-releases.md#the-release-tree)):

```text
release.json          # seal manifest, ai.wisent.tama.hook-release.v1
package.json          # hook package identity (@wisent/tama)
shared-hooks/         # registry.json, hook scripts, session supervisor,
                      # universal runtime, OMP adapter, Node preflight
claude-hooks/         # provider-specific entrypoints
codex-hooks/
repo-githooks/<project>/
external-hooks/       # approved sources packaged from outside the managed roots
external-sources.json # sourcePrefix -> releasePath mappings
bin/tama-cli          # sealed Rust CLI (the desktop backend)
bin/tama-mcp-server   # sealed MCP server
```

The identity is the content: `releaseId` in `release.json` is the tree
digest defined in [concepts/seal](seal.md). The release sealed on
2026-08-24 in this checkout digests to
`35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7` — the
value every capture in the [walkthroughs](../walkthrough-verify-release.md)
shows.

## Who declares it

Hook policy is authored outside this repository, in the hook source tree
`Scripts/build-app.sh` selects with `TAMA_HOOK_ROOT` (default: the `tama`
checkout beside this repository — the tree whose generated documentation is
titled the Hooks Rotator catalog). The build stages the four hook
directories, compiles `tama-cli` and `tama-mcp-server` from that tree's
`rust/` workspace, packages external sources, prunes generator files and
bytecode, and seals ([scripts](../scripts.md#build-appsh)). The desktop
release then *carries* the hook release; the two have separate identities
and version policies ([releases](../releases.md#product-and-hook-identities)).

## Who installs it

Only an explicit operator action, through `install_hook_release.py`
([scripts](../scripts.md#install_hook_releasepy)). Installation is:

- **gated** — bundled digest, then installed digest, refusing verbatim at
  either ([concepts/seal](seal.md#who-enforces-it));
- **content-addressed** — the tree lands at
  `~/Library/Application Support/Tama/hooks-runtime/releases/<release-id>`
  with a `current` symlink replaced atomically;
- **rewritten** — every registry path is mapped from the canonical source
  root and home to the target home, Node-based hook commands are pinned to a
  validated Node.js 20+ executable with the version-guard preflight, and
  `catalogChecksum` is recomputed;
- **transactional** — every touched file is backed up and restored on
  failure, and obsolete files are deleted only under the managed roots.

The full write set is in [hook-releases](../hook-releases.md#installation).

## Who observes it

- `installed.json` (schema `ai.wisent.tama.installed-hook-release.v1`)
  records the installed identity, managed files, and pinned Node.
- Every live session record carries `runtime.installedReleaseId`,
  `runtime.loadedReleaseId`, and `runtime.catalogChecksum` — what the
  session actually loaded, not what should have been loaded.
- [Posture](../desktop/posture.md) compares bundled vs installed vs loaded;
  [walkthrough-runtime-status](../walkthrough-runtime-status.md) is the
  command-line version.
- `verify_installed_releases.py` digests every installed tree against its
  directory name — no manifest needed, because the name is the claim.

## Where it lives

| Location | Copy |
|---|---|
| `Tama.app/Contents/Resources/hooks-release/` | The bundled release, sealed at build time; authoritative for the catalog at runtime |
| `~/Library/Application Support/Tama/hooks-runtime/releases/<id>/` | Content-addressed installed copies; old ones are retained |
| `~/Library/Application Support/Tama/hooks-runtime/current` | Atomic symlink to the active release |
| `~/.shared-hooks`, `~/.claude/hooks`, `~/.codex/hooks`, `~/.local/bin/tama-agent`, Git hook paths | The installed entrypoints generated *from* the release |

## Commands

```bash
python3 Scripts/verify_hook_release.py                       # bundled tree vs its seal
python3 Scripts/report_hook_release_integrity.py             # same, with residue attribution
python3 Scripts/verify_installed_releases.py                 # every installed tree vs its name
Tama.app/Contents/Resources/hooks-release/bin/tama-cli list  # what the release declares
```

## Not to be confused with

- **The product release.** `Tama-<version>-macOS-<arch>.zip` is the signed
  desktop artifact; it *contains* one hook release. Upgrading the app can
  ship the same hook release, and a new hook release requires a new app
  artifact — hooks never update in place ([releases](../releases.md)).
- **The installed runtime.** `~/.shared-hooks` and its siblings are
  *generated from* a release (paths rewritten, Node pinned); they are not the
  release and are not content-addressed. The release copy under
  `hooks-runtime/releases/` is the verifiable original.
- **The registry.** `shared-hooks/registry.json` is one file inside the
  release — the declaration of what the release enforces
  ([concepts/registry](registry.md)); the release is the deployable unit
  that carries it.
