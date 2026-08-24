# Session-scoped enable

How does Tama change what runs in a live agent session — and why can it only
ever make policy stronger there? Through one narrow mutation: enable a hook,
or every hook, in exactly one session, applied not by Tama but by that
session's own supervisor. There is no per-session disable, by contract
([core-contracts](../core-contracts.md#session-override)).

## What it is

A private file-based request/response exchange in
`~/Library/Application Support/Tama/session-control/` (directory mode
`0700`, files `0600`). Tama writes
`<controlKey>.<requestId>.request.json` and polls every 0.05 s, for at most
10 s, for the matching `<controlKey>.<requestId>.response.json`. The request
carries `schema` (`ai.wisent.tama.session-control.v2`), `sessionId`,
`controlKey`, `requestId` (UUID), `confirmed: true`, `operation`, and for
`set-hook` the `hookId` with `enabled: true`. The response carries `schema`,
`requestId`, `ok`, `error`, and `state` — the authoritative session record
after the change.

Two operations exist:

- `set-hook` — enable one registered hook id in this session;
- `enable-all` — enable every registered hook and schedule one runtime
  reload after the active agent turn settles; concurrent reloads coalesce,
  and a failure restores the preceding override state.

Retrying the same enable is idempotent.

## Who applies it

The session's own supervisor — never Tama. The supervisor validates the
envelope against the exact identity tuple in its session record
([enforcement-control](../enforcement-control.md#session-records)): the
`controlKey` is a 64-hex secret, the `agentId` must start with an ASCII
letter and be 1–32 characters, and the record must be live (`process` mode:
the pid answers `kill(pid, 0)`; `heartbeat` mode: `updatedAt` within
`heartbeatTTLSeconds`, clamped to 5–3600, default 900). It applies the
override atomically as `<controlKey>.override.json` and answers with the
resulting state.

## What can refuse it

Every failure is actionable, never optimistic — the exact sentences, from
`SessionControlClient`:

| Failure | Sentence |
|---|---|
| Malformed session identity | `Tama rejected an invalid agent session control endpoint.` |
| Unparseable response | `The agent runtime returned an invalid session-control response.` |
| Only v1 records on disk | `Tama found only legacy v1 session records. Reinstall the verified bundled runtime, then stop or resume the affected agent session to publish v2 state.` |
| Supervisor said no | `The agent runtime rejected the session-control request: <reason>` |
| 10 s deadline passed | `The agent runtime did not acknowledge the session-control request before the deadline.` |
| Session exited mid-request | `The agent session ended before the session-control request completed.` |

## Semantics under global disable

Enablement is interpreted against `globallyDisabled`
([enforcement-control](../enforcement-control.md#session-scoped-enable)):

- normally, a hook runs unless its id is in `disabledHookIds`;
- during a [global emergency disable](emergency-disable.md),
  `enabledHookIds` is the session's explicit allowlist — the only hooks that
  run. `tama-cli sessions` prints exactly this (`allowlist: empty` for a
  bypassed session with nothing re-enabled;
  [walkthrough-runtime-status](../walkthrough-runtime-status.md#1-live-sessions-from-the-sealed-cli)).

## Where it surfaces

- The **Session** screen's only mutations are *enable one hook here* and
  **Enable all hooks** (offered whenever a session lags the installed
  release); the screen states it can never disable a hook or issue, extend,
  or revoke a capability ([desktop/session](../desktop/session.md)).
- The **Hooks** inspector offers the same single-hook enable in the selected
  session ([desktop/hooks](../desktop/hooks.md)).
- Inside an OMP session, the bundled adapter exposes the same plane as
  session tools: `tama_set_session_hook`,
  `tama_enable_all_session_hooks`, `tama_hook_runtime_status`,
  `tama_request_session_capability`, `tama_reload_hook_runtime` — and
  states that session hook disablement is prohibited.

## Not to be confused with

- **Disabling.** The opposite direction exists only as the machine-global,
  operator-confirmed [emergency disable](emergency-disable.md). Agent-facing
  controls never weaken policy.
- **A capability.** Enabling changes *which hooks run*; a
  [capability](capability.md) grants *what the session may do* under the
  hooks that run. They travel in the same session record and are otherwise
  independent.
- **Installing.** Enable-all binds its override to the installed release and
  checksum, but it does not install anything; a session running an older
  release needs the reload that enable-all schedules, not a new install.
