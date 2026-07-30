# Inspect one live supervised session

## Goal

Confirm which exact policy release and hook set one live coding-agent session is using,
without changing its override.

## Status

Draft for the first `0.2.x` preview. Live-supervisor execution evidence is pending.

## Risk

Read-only and device-level. Reading the session-control record does not authorize writing
an override.

## Environment

Supported Tama installation on Apple-silicon macOS 14 or newer with the local runtime and
backend configured, plus one supported Claude, Codex, OMP, or compatible supervised
session started by its normal launcher.

## Preconditions

- Complete the first-success example.
- Keep exactly one known qualification session live where practical.
- Do not edit files under `session-control` manually.

## Inputs

Select the session by the agent display name, project path, and session ID shown by Tama.
No session ID or control key is typed or copied into a command.

## Artifacts and side effects

Reads bounded `*.session.json` state owned by the supervisor. Refresh may discard stale or
invalid records according to the documented lifecycle; it does not create an override.

## Steps

1. Open **Hook catalog** and select any registered hook.
2. Open **Session control**.
3. Choose **Refresh sessions**.
4. Select the intended session by matching its agent, project path, and session ID.
5. Inspect privileged backend status, system-policy status, liveness mode, heartbeat age,
   capability lifetime and remaining uses, loaded and installed release IDs, catalog
   checksum, registered/loaded/enabled/disabled hook counts, unknown hooks, event state,
   registry error, and reload requirement.
6. Do not press a hook enable/disable control or **Enable all hooks and reload**.

## Verification

For a ready session, the backend must be **Enabled**, policy **Kernel-gated**, session
**Structurally valid**, loaded and installed release prefixes equal, loaded hook count
equal registered hook count, unknown hook count be zero, and neither registry error nor
reload requirement be present. The selected session ID must remain unchanged after one
refresh.

## Failure path

If no session appears, start or resume it normally and refresh. If **Reload required** is
visible, stop and resume that session after confirming installed release identity. If a
registry error or unknown hook appears, do not write an override; preserve bounded status
and diagnose the supervisor/catalog compatibility contract.

## Cleanup or off-switch

Close Tama or leave it open. Stop the qualification agent session when it is no longer
needed. No override or product state was created by this example.

## Next

Change one hook only with
[`control-one-session-hook.md`](control-one-session-hook.md), or inspect policy definitions
with [`inspect-approved-policy.md`](inspect-approved-policy.md).
