# Registry

Where is the single declaration of what runs, when, and why? In
`shared-hooks/registry.json` at the release root — one JSON document that
both the runtime executes from and the human audits from. Everything the
desktop shows about hooks derives from it.

## What it is

The sealed registry in the release built on 2026-08-24 has these top-level
fields (read directly from the sealed file):

| Field | Content |
|---|---|
| `version` | Registry schema version (`1`) |
| `generatedAt`, `generatedFrom`, `managedBy` | Provenance; `managedBy` is `jeden-unified-hooks` — the registry is generated, never hand-edited |
| `releaseId` | Stamped by the installer with the release's seal |
| `catalogChecksum` | SHA-256 of the registry JSON with this field removed (sorted keys, canonical separators) |
| `events` | The execution wiring: 24 event names, each `{blocking, hooks[]}` — what the runtime actually dispatches |
| `adapters` | Provider config paths for `claude`, `codex`, `omp` (removed by the installer after rewriting) |
| `catalog` | The human-auditable record (below) |

`catalog` carries `agentHooks[]` (54 entries in this release), `gitHooks[]`
(6 entries — `id`, `event`, `scope`, `hooksPath`, `source`, plus the shared
category/description/why/side-effect record), `editorAdapters`,
`ompAdapters`, `maintainedIn` (the canonical source path of the registry
itself), `generatedDocs`, `version`, `updatedAt`, and `notes`.

The `events` map and the `catalog` are deliberately redundant: the first is
what executes, the second is what a human approves. `tama-cli validate`
cross-checks them and reports `install drift` when the catalog declares a
hook for an event that no runtime adapter installs
([cli](../cli.md#read-only-commands)).

## Who declares it

The hook source tree (Hooks Rotator). The registry's own `maintainedIn`
names its canonical path, and that self-reference is load-bearing: the
installer derives the source root to rewrite *from* `maintainedIn` and the
canonical home from `adapters.codex.path`, refusing when either does not
look like itself — `Hook registry does not identify its canonical source
root` / `Hook registry does not identify its canonical home`
([runbook](../runbook.md#the-installer-refuses)).

## Who rewrites it

`install_hook_release.py`, once per install, in memory and then atomically
to `~/.shared-hooks/registry.json` (mode `0644`):

1. every path is mapped from the canonical source root and home to the
   target home, external-hook prefixes first (longest match wins), with
   shell-quoting applied inside `command` strings;
2. every Node-based `command` is pinned to the validated Node executable
   with `--require node-runtime-preflight.cjs`;
3. `releaseId` is stamped, `ompAdapters` and `adapters` are dropped,
   `generatedDocs` is set to `~/.shared-hooks/HOOKS.md`;
4. `catalogChecksum` is recomputed over the result.

The checksum therefore identifies the *installed* registry — same release,
different home, different checksum — and every session record carries it, so
identity comparison never assumes the rewrite happened correctly.

## Who reads it

- The session supervisor and universal runtime execute from the installed
  registry (`AGENT_HOOK_REGISTRY` overrides the default
  `~/.shared-hooks/registry.json` for the OMP adapter).
- The sealed CLI answers `list`, `show`, `validate`, `docs`, `install-plan`,
  and the `/v1/coverage` endpoint from the release's registry
  ([cli](../cli.md)).
- The desktop never parses the registry directly: it loads the build-time
  snapshot `tama-catalog.json`, rendered by `Scripts/export-catalog.mjs`
  running `tama-cli list --json` ([hook-model](../hook-model.md#the-desktops-catalog-snapshot)).
- The emergency switch reads the *installed* registry's `catalog.gitHooks[]`
  to know which Git entrypoints to move aside
  ([concepts/emergency-disable](emergency-disable.md)).

## Where it lives

| Copy | Path | State |
|---|---|---|
| Sealed | `<release>/shared-hooks/registry.json` | Canonical source paths; covered by the seal |
| Installed | `~/.shared-hooks/registry.json` | Rewritten for this home; checksummed |
| Snapshot | `Tama.app/Contents/Resources/tama-catalog.json` | Normalized render for the desktop |

## Not to be confused with

- **The catalog snapshot.** `tama-catalog.json` is derived and normalized
  (`category` defaults to `Uncategorized`, `status` to `unknown`, missing
  timeouts to `0`); the registry is the declaration. Validation of the
  snapshot is structural only — the desktop itself states `Bundled snapshot
  only: high-entropy and live runtime drift checks are not run in Tama.`
- **`HOOKS.md`.** Generated documentation rendered *from* the registry
  (`tama-cli docs`; installed at `~/.shared-hooks/HOOKS.md`), titled
  “Hooks Rotator Catalog”. Prose, not policy.
- **Provider configs.** `~/.claude/settings.json` and `~/.codex/hooks.json`
  are generated adapters that point events at the runtime; the registry is
  what the runtime consults once invoked.
