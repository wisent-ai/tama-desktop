# Change one hook in one live session

## Goal

Enable or disable one registered hook for one selected live session and prove every other
session is unaffected.

## Status

Draft for the first `0.2.x` preview. Live-supervisor and adapter evidence are pending.

## Risk

Credentialed security mutation. The operation changes one atomic per-session override and
can alter which policy runs for that session.

## Environment

Supported Tama installation with an enabled backend, one valid selected session, at least
one comparison session when available, and a catalog hook registered by the selected
agent adapter.

## Preconditions

- Inspect the target with [`inspect-live-session.md`](inspect-live-session.md).
- Record the selected session ID, target hook ID and current enabled state.
- Confirm the hook purpose, side effects, and blocking behavior in **Hook catalog**.
- Stop if the session is stale, reload-required, structurally invalid, or has a registry
  error.

## Inputs

The UI supplies the catalog hook ID, accepted session ID, opaque control-key binding,
loaded release, checksum, capability, and requested Boolean state. Users must not type or
reuse a control key.

## Artifacts and side effects

Atomically writes the selected session's `<controlKey>.override.json` with per-user
permissions. It preserves the session capability and binds the override to agent, session,
release, and catalog identity. Other session files are not targets.

## Steps

1. In **Hook catalog**, select the target hook and open **Session control**.
2. Select the exact target session.
3. Read the dialog scope: agent, session ID, project, hook ID, and resulting effect.
4. Change the hook control to the requested state and confirm.
5. Refresh sessions after the supervisor consumes the override.
6. Select the comparison session, if available, and inspect the same hook without changing it.

## Verification

The target session must report the requested hook in the expected enabled or disabled set,
retain the same agent/session/control binding, and show no registry error. A comparison
session must retain its prior state. An accepted button action without refreshed state is
not success.

For adapter qualification, the supervisor must also prove it rejects an override whose
control key, session ID, release ID, catalog checksum, lifetime, or remaining-use limit is
invalid. Never create such a record in a real user state directory; use the adapter's
controlled qualification environment.

## Failure path

If Tama reports an invalid or unavailable session, refresh and select the new live record;
do not retry against stale identity. If the hook is unknown or unregistered, return to the
catalog/adapter compatibility diagnosis. If atomic write fails, preserve the old override
and retry only after fixing the reported filesystem condition.

## Cleanup or off-switch

Restore the target hook to its recorded starting state through the same confirmed UI and
refresh until that state is visible. Stop any disposable comparison session.

## Next

To restore the complete registered set in one selected session, follow
[`enable-all-hooks-one-session.md`](enable-all-hooks-one-session.md). For a global blocking
failure, use
[`../recovery/emergency-disable-and-reenable.md`](../recovery/emergency-disable-and-reenable.md).
