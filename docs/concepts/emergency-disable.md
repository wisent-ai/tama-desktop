# Emergency disable

When a hook blocks work that genuinely must proceed, what is the recovery —
and what does it cost? One confirmed, operator-owned action that bypasses
every Tama-managed dispatcher on the machine, records exactly what it moved,
and stays visible until a verified re-enable restores everything. It is
deliberately the only way to weaken policy: sessions can
[enable](session-enable.md), only operators can disable, and only globally
([enforcement-control](../enforcement-control.md)).

## What it is

`emergency_disable_hooks`, a bundled POSIX script the desktop runs from
**Posture** and re-runs with `TAMA_EMERGENCY_ACTION=enable` for re-enable
([scripts](../scripts.md#emergency_disable_hooks)). Disable, in order:

1. pauses every supervised session
   (`agent-session-supervisor.py control pause --require-all`); an exit trap
   resumes them after success, failure, or interruption;
2. reinstalls the session controllers
   (`install_hook_release.py --session-control-only`) so session visibility
   survives the bypass;
3. backs up `~/.claude/settings.json` and `~/.codex/hooks.json` into
   `emergency-backup/` and empties their `hooks` maps;
4. moves entrypoints aside to `<name>.tama-disabled`: the OMP agent hooks
   directory and every Git hook source the installed
   [registry](registry.md) declares;
5. stops the editor watcher (the `~/.shared-hooks/editor-hooks.pid` process,
   then the `com.wisent.editor-hooks.plist` LaunchAgent);
6. writes `emergency-backup/manifest.json` once and
   `hook-emergency-state.json`
   (`ai.wisent.tama.hook-emergency-state.v1`, `disabled: true`, `changedAt`).

Success prints `Disabled hooks. Supervised agent sessions will resume
without an editor restart.`; repeating it prints `Tama hooks are already
disabled.` and changes nothing.

## What it costs

The desktop's confirmation states the price before the button exists —
title `Disable every Tama hook on this machine`, then verbatim:

- `Agent, editor and Git dispatchers will bypass all <N> policies until the
  approved release is verified and reinstalled.`
- `<N> blocking hooks will stop refusing unsafe work, including in sessions
  that are running right now.`
- `Supervised sessions keep running. Their per-session overrides survive,
  and Tama restores them when the release is reinstalled.`

with reason code `hook-emergency-state.v1 disabled=true`, the full listing
of blocking hook ids, the footnote `recovery files are preserved under
Application Support/Tama/emergency-backup`, and three actions: `Read the
blocking decision` (jumps to [Session](../desktop/session.md)),
destructive `Disable all hooks`, primary `Keep policy active`.

## How state is judged

Tama treats the machine as disabled only when **both** the manifest and the
state file exist, and it re-reads that durable state after the script
returns — `Tama could not persist the emergency hook state.` is a failure,
never claimed success. During the bypass, a session's
`enabledHookIds` allowlist is the only policy that runs
([session-enable](session-enable.md#semantics-under-global-disable)).

## Re-enable

Enable refuses without evidence: no manifest answers `Tama has no emergency
backup manifest to restore.`, and the bundled release must pass its
[seal](seal.md) gates. It performs the full transactional installation with
`--emergency-manifest` — restoring every moved entrypoint, regenerating
provider configs from the backups, re-bootstrapping the editor LaunchAgent —
and only then removes the state file and manifest, printing `Enabled
approved hook release <first-12>. Supervised agent sessions will resume
without an editor restart.` A failed enable preserves the recovery evidence.

## Where it lives

| Path | Content |
|---|---|
| `~/Library/Application Support/Tama/hook-emergency-state.json` | The durable disabled flag |
| `~/Library/Application Support/Tama/emergency-backup/manifest.json` | `configs` emptied, `moved` entrypoint pairs, `editorWatcherStopped` — written once |
| `~/Library/Application Support/Tama/emergency-backup/claude-settings.json`, `codex-hooks.json` | Original provider configs, restored on enable |

The desktop wrapper (`HookEmergencySwitch`) bounds the script: 300 s
runtime, 64 KiB output, SIGTERM→SIGKILL escalation, with its own verbatim
failures (`The local policy command exceeded its bounded runtime and was
terminated. Inspect local policy state before retrying.`, `The Tama bundle
does not contain the emergency hook controller.`, …) listed in the
[runbook](../runbook.md#the-emergency-switch-refuses).

## Not to be confused with

- **Deactivate.** **Settings → Deactivate everything** runs this same global
  disable *and then* unregisters the privileged daemon, System Extension,
  and network filter independently ([desktop/settings](../desktop/settings.md)).
  Emergency disable alone leaves the privileged backend registered.
- **A per-session disable.** Does not exist, anywhere in the product
  ([core-contracts](../core-contracts.md#safety-and-authorization)).
- **Uninstalling.** The bypass moves entrypoints aside and empties config
  maps; every byte needed to restore enforcement stays on disk, deliberately
  ([operations](../operations.md#reset-and-uninstall)).
