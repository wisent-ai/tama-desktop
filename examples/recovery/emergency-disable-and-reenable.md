# Emergency-disable managed hooks and restore them safely

## Goal

Recover from a blocking policy failure by bypassing every Tama-managed dispatcher, then
restore the exact integrity-checked bundled release and supervised sessions.

## Status

Draft for the first `0.2.x` preview. Destructive controlled-device execution evidence is
pending.

## Risk

Security mutation, destructive/recovery, and device-level. While disabled, managed agent,
editor, and Git dispatchers bypass policy. Re-enable can make blocking policy active again.

## Environment

Supported Tama installation with an installed runtime and at least one safely stoppable
supervised session. Use a controlled repository and session; never induce a policy failure
in production work merely to run this example.

## Preconditions

- Record product version/source revision, installed and bundled hook release IDs, catalog
  checksum, live session IDs, and enabled/disabled state.
- Save unrelated work and ensure supervised sessions can pause and resume.
- Confirm the app bundle and installed release are not being modified concurrently.

## Inputs

The scope is every Tama-managed dispatcher for the current user. No path or hook subset is
accepted. The two separate confirmation dialogs are the authorization boundaries.

## Artifacts and side effects

Disable records `hook-emergency-state.json`, preserves moved entrypoints under
`emergency-backup`, pauses/resumes supervised sessions, and bypasses managed dispatchers.
Re-enable verifies and installs the bundled hook release transactionally, restores managed
entrypoints, removes emergency state only after success, and resumes sessions.

## Steps

1. In Tama's toolbar, choose **Disable all hooks**.
2. Read the destructive confirmation and confirm.
3. Observe the red **ALL HOOKS DISABLED** banner and confirm supervised sessions resumed.
4. Perform only the bounded recovery action that the blocked policy prevented.
5. Choose **Re-enable all hooks** from the banner or toolbar.
6. Read the restore confirmation and choose **Install approved release and re-enable**.
7. Refresh sessions; stop/resume only sessions that explicitly report reload required.

## Verification

After disable, the durable emergency state and visible banner must agree; a partial command
without resumed sessions is failure. After re-enable, the banner must disappear, bundled
and installed release IDs must match, managed entrypoints must be restored, emergency state
must be cleared, and live sessions must show no registry error or reload requirement.

## Failure path

If disable partially fails, the exit trap must resume sessions. Preserve
`emergency-backup` and the manifest; do not delete or rewrite them. Retry re-enable only
from the same verified app version after fixing the reported condition. If integrity
verification fails, follow [`recover-integrity-failure.md`](recover-integrity-failure.md)
instead of manually restoring dispatchers.

## Cleanup or off-switch

The intended cleanup is successful re-enable. Confirm no emergency banner or manifest
remains. If policy must remain disabled for an incident, record that explicit retention
decision and do not represent the product as enforcement-ready.

## Next

Inspect the restored session with
[`../core/inspect-live-session.md`](../core/inspect-live-session.md).
