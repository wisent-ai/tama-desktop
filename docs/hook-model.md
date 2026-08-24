# Hook model

What exactly is a hook, and where is it declared? A hook is one approved
policy command bound to one or more agent events, described by a registry
that ships sealed inside every release. This page is the registry model;
sealing and installation are in [hook-releases](hook-releases.md), and the
runtime controls are in [enforcement-control](enforcement-control.md).

## The registry

`shared-hooks/registry.json` at the release root is the single declaration.
Its top-level fields are `version`, `generatedAt`, `generatedFrom`,
`managedBy`, `releaseId`, `catalogChecksum`, `events` (the per-event hook
wiring the runtime executes), `adapters` (provider config paths), and
`catalog` — the human-auditable record.

`catalog` carries:

- `agentHooks[]` — the approved agent-facing hooks (below);
- `gitHooks[]` — repository Git hooks: `id`, `event`, `scope`, `hooksPath`,
  `source`, plus the same category/description/why/side-effect record;
- `editorAdapters` and `ompAdapters` — where editor and OMP integrations
  attach;
- `maintainedIn` — the canonical source path of the registry itself, which
  the installer uses to recognize the source root it must rewrite;
- `generatedDocs` — where the rendered hook documentation lives
  (`~/.shared-hooks/HOOKS.md` after installation);
- `version`, `updatedAt`, `notes`.

`catalogChecksum` is the SHA-256 of the registry JSON with the checksum
field itself removed (sorted keys, canonical separators). It is recomputed
by the installer after path rewriting, and every session record carries it,
so the desktop can compare the bundle, the installed runtime, and the live
session by checksum rather than by trust.

## One agent hook

Each `agentHooks[]` entry declares:

| Field | Meaning |
|---|---|
| `id` | Stable hook identity, e.g. `block-inline-execution` |
| `command` | The exact command the runtime executes |
| `source` | The hook's source file inside the release |
| `occurrences[]` | Every event binding: `event`, `blocking`, `timeout`, `statusMessage` |
| `category` | Policy area, e.g. `git safety`, `credential safety`, `edit safety` |
| `status` | Lifecycle state (`active`) |
| `description`, `why`, `sideEffects` | What it does, the justification for it, and what it touches |
| `aliases` | Alternate ids the runtime accepts |

Events are names like `pre_tool_use:bash`, `pre_tool_use:write`,
`user_prompt_submit`, or `stop`. A binding with `blocking: true` can refuse
the action; its `timeout` is the hook's execution budget in seconds and
`statusMessage` is what the agent surface shows while it runs. Hooks read a
JSON payload from stdin and fail closed: a blocking hook exits non-zero or
returns a deny decision when its invariant is violated.

## The desktop's catalog snapshot

The app does not parse the registry directly. At build time,
`Scripts/export-catalog.mjs` renders it into `tama-catalog.json` inside the
app resources: `version`, `generatedAt`, `hooks[]`, `orphanSources[]`
(source files no hook references), and `repoGitHooks[]` (`project`, `event`,
`sourcePath`). Each snapshot hook carries `id`, `type`, `command`,
`sourcePath`, `category`, `status`, `description`, `why`, `sideEffects`,
`events[]`, and `justificationRequirements[]`.

On every load the app validates the snapshot structurally: duplicate hook
ids and hooks with no events are errors; a hook whose source path cannot be
mapped from its command is a warning. The result — ok flag, errors,
warnings, hook count, orphan-source count — is what **Posture** shows as
*Structural validation*, with the standing warning that the bundled snapshot
check does not run high-entropy or live runtime drift checks.

## Justification-gated hooks

A hook of type `requires_justification` names one or more local
justification registries instead of blocking outright. Each requirement
declares `kind`, `title`, `registryPath` (a `~`-relative JSON file),
`field` (the justification text field), `minimumWords`, and optionally
`directUserQuoteField`. The desktop's **Justifications** screen reads those
registries and shows every entry with its word count, its `expires_at`
expiry, and whether the target it justifies still exists — expired or
missing-target entries are the ones to renew or remove.

## Generated documentation

`tama-cli docs` renders the full per-hook documentation from the registry
plus the archived source tree; the installed runtime keeps the same render
at `~/.shared-hooks/HOOKS.md`. `tama-cli list`, `show <hook-id>`, and
`validate` are the terse forms ([cli](cli.md)).
