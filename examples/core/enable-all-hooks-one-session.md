# Enable every registered hook in one selected session

## Goal

Restore the complete registered hook set for one live session and require that session to
reload, without changing other sessions.

## Status

Draft for the first `0.2.x` preview. Live-supervisor execution evidence is pending.

## Risk

Credentialed security mutation. Enabling blocking hooks can interrupt the selected agent;
the operation is intentionally scoped to one session.

## Environment

Supported Tama installation with an enabled backend and one accepted live session whose
registered set contains at least one disabled hook.

## Preconditions

- Record the selected session ID, project, registered count, enabled count, and disabled IDs.
- Inspect the purpose and side effects of every hook that will transition to enabled.
- Ensure the selected agent can be safely stopped and resumed.

## Inputs

The selected session in Tama is the complete scope. Do not infer scope from the project
path alone; verify agent and session ID in the confirmation.

## Artifacts and side effects

Atomically replaces that session's override with all registered hooks enabled and no
registered hooks disabled. The selected supervisor may need a stop/resume cycle to load the
new state. Other sessions are not targets.

## Steps

1. Open **Session control** and select the exact live session.
2. Choose **Enable all hooks and reload**.
3. Review the confirmation, including selected agent and session, then confirm.
4. Stop and resume only that supervised session if Tama reports **Reload required**.
5. Refresh sessions and select the resumed record.

## Verification

Enabled hook count must equal registered hook count, disabled hook count must be zero,
unknown hook count must be zero, and **Reload required** plus registry error must be absent.
A second live session, when present, must retain its original counts.

## Failure path

If the record expires or changes identity before confirmation, cancel, refresh, and review
the new record. If reload remains required after a normal stop/resume, compare loaded and
installed release IDs and catalog checksum before any retry.

## Cleanup or off-switch

If qualification changed a deliberately disabled hook, restore the recorded starting state
one hook at a time through [`control-one-session-hook.md`](control-one-session-hook.md).
Otherwise retain the all-enabled state as the declared result.

## Next

Inspect the stable result with [`inspect-live-session.md`](inspect-live-session.md).
