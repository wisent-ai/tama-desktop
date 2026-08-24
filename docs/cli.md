# CLI

This page documents the sealed Rust CLI the desktop release bundles at
`Tama.app/Contents/Resources/hooks-release/bin/tama-cli`, built and signed
by `Scripts/build-app.sh` from the same hook source tree as the release
itself, so the binary the app runs is the one the build sealed. Its usage
line reads `tama <command>`. Runnable, commented examples for the public
outcomes live in [`../examples/`](../examples/); the contract behind each
command is in [core-contracts](core-contracts.md).

## Read-only commands

| Command | Answer |
|---|---|
| `list [--json]` | Every catalog hook: id, source path, events |
| `show <hook-id> [--json]` | One hook in full |
| `validate [--json]` | Catalog/source-archive validation: hook and orphan-source counts, one warning per unmappable source path |
| `docs [--out <path>]` | The rendered per-hook documentation ([hook-model](hook-model.md)) |
| `install-plan [--json]` | Runtime scopes and target paths, per level: agent/app, editor, MCP, user-global Git, repo/project Git, OS-level |
| `mcp-config` | The MCP server config snippet naming the bundled `tama-mcp-server` |
| `sessions [--json] [--home <path>]` | Every live agent session and its hook state |
| `verify` | Catalog validation plus hook block fixtures |

## Mutating commands

`install` writes the user-global Git dispatchers (`pre-commit`, `pre-push`)
into the resolved hooks path and reports it; `--set-git-config` additionally
writes the Git configuration. Without the flag, Git config is untouched and
the output states `git global config updated: false`.

## Repository scans and cleanup

```
tama find-violations (--repo <path> | --tree <dir> | --owner <gh-owner> | --me)
                     [...] [--json] [--hook <path>] [--clone-dir <dir>]
```

Replays the real bundled pre-write hook against every enumerated file and
reports the first violation per file; it never modifies scanned
repositories. Targets are repeatable and combinable: one repository, every
Git checkout under a tree, every GitHub repository of an owner (via the `gh`
CLI, shallow-cloning missing checkouts into `--clone-dir`), or `--me` for
the authenticated user plus their orgs. Command-gating hooks stay out of
scope by design — they gate shell commands, not file content.

```
tama clean (same targets) [--model codex|kimi] [--max-rounds <n>]
           [--skip <fragment>] [--note <text>] [--dry-run] [--json]
```

Scans, then spawns one headless model agent per repository per round to fix
violations, re-scanning after each round until clean or out of rounds. The
agent edits with hooks active, rounds that game the rules are rejected and
fed back, generated files are never handed to the agent, `--dry-run` prints
the brief without spawning anything, and `TAMA_CLEAN_DISABLED=1` disables
the command entirely. The desktop's **Violations** screen drives the same
engine and adds its own repository-ownership and confirmation gates
([desktop](desktop.md)).

## The desktop backend

`serve [--port N]` runs the loopback HTTP backend the desktop spawns as
`tama-cli serve --port 0 --root <release>`: it binds `127.0.0.1`, prints one
ready line `{"ready":true,"port":N}`, then serves `/v1` until killed.

| Endpoint | Method | Body | Answer |
|---|---|---|---|
| `/v1/coverage` | GET | — | Registry-declared provider/event/hook mappings |
| `/v1/install-plan` | GET | — | `archiveRoot` plus per-level scope targets |
| `/v1/mcp-config` | GET | — | The MCP snippet |
| `/v1/violations/scan` | POST | `{"repo": <path>}` | NDJSON stream; result status 0 = clean report, 1 = report with violations |
| `/v1/violations/clean` | POST | `{"repo": <path>}` | NDJSON stream; result status 0 = cleanup summary |

Stream events are `{"type":"log","stream":"stdout"|"stderr","chunk":…}` and
exactly one `{"type":"result","status":…,"json":…}`; a non-2xx response
carries `{"error":"<one sentence>"}`.

## Adaptive layer doctor

`adaptive <command>` inspects and repairs the adaptive hook layer:

- `status` — per-hook tier, mode, projected state, telemetry transport;
- `drift` — live hook scripts vs repository archive content hashes;
- `queue` — queued repair requests;
- `repair <hook-id> [--patch-file <path>]` — draft and validate a repair
  proposal;
- `apply <proposal-dir>` — apply a validated proposal (owner consent
  required);
- `install` / `uninstall` — manage the legacy-runner shim (owner consent
  required);
- `claude-config` — print the Claude settings routing fragment.

The runnable example with its safety notes is
[`../examples/recovery/adaptive-status.sh`](../examples/recovery/adaptive-status.sh).
