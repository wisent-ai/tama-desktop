# Enforcement control

Tama has exactly two enforcement mutations, and they point in opposite
directions on purpose. Enabling is narrow: one hook, or all hooks, in one
live session, applied by that session's own supervisor. Disabling is global:
one confirmed emergency action that bypasses every managed dispatcher on the
machine and leaves durable evidence until re-enable succeeds. There is no
per-session disable — agent-session controls never weaken policy, and
disabling enforcement remains an operator-owned action outside the session
([core-contracts](core-contracts.md)).

## Session records

Supervised runtimes publish one file per live session under
`~/Library/Application Support/Tama/session-control/` (directory mode
`0700`), schema `ai.wisent.tama.session-control.v2`. A record carries
`agentId`, `sessionId`, a 64-hex `controlKey`, `pid`, `cwd`, `livenessMode`
(`process` — the pid must be alive — or `heartbeat` — `updatedAt` within
`heartbeatTTLSeconds`, clamped to 5–3600), `globallyDisabled`,
`disabledHookIds`, `enabledHookIds`, the session's `capability` (issuer,
nonce, release and checksum binding, lifetime, expiry, remaining uses, and
per-tool grants), `runtime` status (`installedReleaseId`, `loadedReleaseId`,
`catalogChecksum`, registered/loaded hook counts, unknown hook ids,
`reloadRequired`, `reloadPending`, `registryLoadError`), and
`semanticRuntime` — the sequence of recent events with each `decision`, the
`blockedHookId`, and the `reason` string. Tama only reads these records;
invalid, legacy-v1, or stale ones are ignored.

## Session-scoped enable

The desktop writes a private request file
`<controlKey>.<requestId>.request.json` (mode `0600`) into the same
directory — operation `set-hook` with `hookId` and `enabled: true`, or
`enable-all` — and polls for the matching
`<controlKey>.<requestId>.response.json` for up to 10 seconds. The
supervisor validates the envelope against the exact session identity tuple,
applies the override atomically, and answers with the authoritative session
state; rejection, malformed identity, session exit, or timeout is an
actionable failure, never optimistic success. Retrying the same enable is
idempotent.

Enablement semantics follow `globallyDisabled`:

- normally, a hook is enabled unless its id is in `disabledHookIds`;
- during a global emergency disable, `enabledHookIds` is the session's
  explicit allowlist — the only hooks that run.

`enable-all` first persists an override bound to the installed release and
catalog checksum, then schedules one runtime reload after the active agent
turn settles; concurrent reload requests coalesce, and a failure restores
the preceding override state. The **Session** screen shows the pending state
until the transition completes, and offers **Enable all hooks** whenever a
session lags the installed release.

Inside an OMP session, the bundled adapter
(`~/.shared-hooks/omp-shared-hooks.js`) exposes the same control plane as
session tools: `tama_hook_runtime_status`, `tama_set_session_hook`,
`tama_enable_all_session_hooks`, `tama_request_session_capability`, and
`tama_reload_hook_runtime`. Session hook disablement is prohibited there
too.

## Global emergency disable

The bundled `emergency_disable_hooks` script is the switch; the desktop runs
it from **Posture** (confirmed as *Disable every Tama hook on this machine*)
and re-runs it with `TAMA_EMERGENCY_ACTION=enable` for re-enable. Disable:

1. pauses every supervised session through
   `agent-session-supervisor.py control pause --require-all`; an exit trap
   resumes them after success, failure, or interruption;
2. reinstalls the session controllers (`--session-control-only`) so session
   visibility survives the bypass;
3. backs up `~/.claude/settings.json` and `~/.codex/hooks.json` into
   `emergency-backup/` and empties their `hooks` maps;
4. moves entrypoints aside to `<name>.tama-disabled`: the OMP agent hooks
   directory and every Git hook source the installed registry declares;
5. stops the editor watcher (`~/.shared-hooks/editor-hooks.pid`, then the
   `com.wisent.editor-hooks.plist` LaunchAgent);
6. records everything once in `emergency-backup/manifest.json` and writes
   `hook-emergency-state.json` (schema
   `ai.wisent.tama.hook-emergency-state.v1`, `disabled: true`,
   `changedAt`).

Repeating disable is idempotent (`Tama hooks are already disabled.`). The
desktop treats the machine as disabled only when both the manifest and the
disabled state file exist, and after the script returns it re-reads that
durable state — a switch that did not persist is reported as a failure, not
claimed as success.

## Re-enable

Enable refuses to run without the emergency manifest and a valid bundled
release. It performs the full transactional installation of
[hook-releases](hook-releases.md) with `--emergency-manifest`, which
restores every moved entrypoint from the manifest, regenerates provider
configs from the emergency backups, re-bootstraps the editor LaunchAgent,
and only then removes the emergency state and manifest. A failed enable
preserves the recovery evidence and does not claim the enabled state.

**Settings → Deactivate** is the composed teardown: it runs the same global
disable and then unregisters the privileged daemon, System Extension, and
network filter independently, so one failure does not skip later cleanup
([desktop](desktop.md)). Restoration evidence under
`~/Library/Application Support/Tama` is deliberately preserved
([operations](operations.md)).
