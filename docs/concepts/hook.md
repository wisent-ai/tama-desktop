# Hook

What is the atom of Tama policy? A hook: one approved command bound to one
or more agent events, with a human record of what it does, why it exists,
and what it touches. Hooks are approved and shipped as a set — one
[hook release](hook-release.md) — never individually.

## What it is

One `catalog.agentHooks[]` entry in the [registry](registry.md). The sealed
release of 2026-08-24 declares 54 of them; each carries exactly these
fields (read from the sealed registry):

| Field | Meaning |
|---|---|
| `id` | Stable identity, e.g. `block-inline-execution` |
| `command` | The exact command the runtime executes (Node commands are pinned at install time) |
| `source` | The hook's source file; empty for hooks compiled into the sealed Rust backend |
| `occurrences[]` | Every event binding: `event`, `blocking`, `timeout`, `statusMessage` |
| `category` | Policy area, e.g. `git safety`, `credential safety` |
| `status` | Lifecycle state (`active`) |
| `description`, `why`, `sideEffects` | The human record |
| `aliases` | Alternate ids the runtime accepts |

A binding with `blocking: true` can refuse the action; `timeout` is its
execution budget in seconds; `statusMessage` is what the agent surface shows
while it runs. Hooks read a JSON payload on stdin and fail closed: a
blocking hook exits non-zero or returns a deny decision when its invariant
is violated. One real hook, from the sealed CLI:

```console
$ tama-cli show block-inline-execution
block-inline-execution
source: shared-hooks/block_inline_execution.sh
command: ~/.shared-hooks/block_inline_execution.sh
does: Blocks throwaway inline programs across shell, Eval, notebook/REPL, browser-run, debugger-evaluate, hub-start, and mounted-device payloads.
why: Executable logic belongs in checked-in, reusable, reviewable files rather than transient tool payloads.
events:
  - pre_tool_use:bash blocking=true
  - pre_tool_use:browser blocking=true
  - pre_tool_use:debug blocking=true
  - pre_tool_use:eval blocking=true
  - pre_tool_use:hub blocking=true
  - pre_tool_use:mcp__node_repl_js blocking=true
  - pre_tool_use:node_repl blocking=true
  - pre_tool_use:notebook blocking=true
  - pre_tool_use:write blocking=true
```

An unknown id answers `not found: <id>` and exits `1`.

## Events

Event names are `<phase>[:<tool>]`: `pre_tool_use:bash`,
`pre_tool_use:write`, `post_tool_use:bash`, `user_prompt_submit`,
`session_start:compact`, `stop`. The sealed registry wires 24 event names in
its `events` map. `stop` hooks gate whether an agent may end its turn;
`pre_tool_use:*` hooks gate a single tool call. Which provider actually
dispatches which event is the [Coverage](../desktop/coverage.md) question —
declared mappings, not live evidence.

## Kinds of hooks

- **Agent hooks** — the 54 `agentHooks[]` above, dispatched by the session
  runtime.
- **Git hooks** — 6 `gitHooks[]` entries installed as `pre-commit`/`pre-push`
  dispatchers at the user-global Git hooks path and approved per-repository
  `.githooks` files ([hook-releases](../hook-releases.md#installation)).
- **Sealed-backend hooks** — catalog entries whose logic is compiled into
  the Rust binaries and therefore have no mappable script path; `tama-cli
  validate` reports one warning per such hook (`WARN <id>: source path could
  not be mapped from command`), which is expected, not drift
  ([cli](../cli.md#read-only-commands)).
- **Justification-gated hooks** — type `requires_justification`: instead of
  blocking outright they demand a recorded justification in a local registry
  file ([hook-model](../hook-model.md#justification-gated-hooks),
  [Justifications](../desktop/justifications.md)). The current sealed
  catalog contains none; the mechanism ships regardless.

## Lifecycle and control

A hook exists in a session in one of three effective states, and the
mutations are deliberately asymmetric
([enforcement-control](../enforcement-control.md)):

- **enabled** — the normal state: registered in the loaded release and not
  in the session's `disabledHookIds`;
- **disabled in one session** — only the session's own supervisor ever does
  this; Tama cannot ([concepts/session-enable](session-enable.md));
- **globally bypassed** — the machine-wide emergency state, where only a
  session's explicit `enabledHookIds` allowlist runs
  ([concepts/emergency-disable](emergency-disable.md)).

Tama's only per-hook mutation is *enable*, in one live session. There is no
per-hook uninstall: removing a hook means shipping a new release without it.

## Not to be confused with

- **An event.** One hook binds to many events with independent blocking
  flags and timeouts; "the hook fired" is meaningless without naming the
  binding.
- **A Git hook dispatcher.** The installed `pre-commit`/`pre-push` files are
  generated dispatchers that chain repository hooks, archived hooks, and a
  preserved `<name>.before-tama` backup; the catalog `gitHooks[]` entries
  are the approved sources they dispatch to.
- **A provider config entry.** `~/.claude/settings.json` and
  `~/.codex/hooks.json` route events to the runtime; deleting a route does
  not unregister the hook — the emergency switch empties those maps *and*
  moves entrypoints aside precisely because both layers exist.
