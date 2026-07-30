# Upgrade to one exact compatible Tama release

## Goal

Replace the current Tama app with one exact newer compatible artifact while preserving
recoverable state and proving the resumed runtime matches the new release contract.

## Status

Draft for the first pair of qualified `0.2.x` previews. Two-version controlled-device
evidence is pending.

## Risk

Destructive/recovery and device-level. An upgrade replaces signed code and may require an
explicit runtime reinstall, component approval, migration, or session reload.

## Environment

Supported Mac with one installed Tama version and a newer immutable artifact plus sidecars
from an exact tag. No second Tama version may run against the same Application Support
state.

## Preconditions

- Record current product version/source revision, installed hook release ID, catalog
  checksum, backend status, and live session identities.
- Read every intervening release note and confirm the migration is cumulative.
- Stop supervised sessions and back up `~/Library/Application Support/Tama` when release
  notes identify a state change.
- Verify the new artifact using [`verify-release-manifests.md`](verify-release-manifests.md).

## Inputs

The old exact artifact/backup and one newer exact compatible artifact. Moving references,
skipped noncumulative migrations, and artifacts with a different architecture are rejected.

## Artifacts and side effects

Replaces `Tama.app`. Opening the new app reads existing per-user state; an explicitly
confirmed install may add a new sealed hook release and atomically update `current` while
retaining prior identity. macOS may request approval for changed signed components.

## Steps

1. Stop all supervised sessions and quit the old Tama.
2. Retain the old artifact and compatible Application Support backup.
3. Replace the app with the verified newer exact artifact.
4. Open Tama and confirm new build identity before any mutation.
5. Read the migration/operator action from release notes.
6. If Overview offers a newer bundled runtime, choose **Install local runtime**, review the
   scope, and confirm.
7. Complete only the named macOS approval when a signed component changed.
8. Start one supported session, refresh, and inspect its loaded state.

## Verification

Overview must show the new exact product/source identity and valid catalog. Installed and
bundled hook release IDs must agree after any explicit install. The resumed session must
show backend **Enabled**, policy **Kernel-gated**, matching release/checksum, no registry
error, and no reload requirement. Merely opening the new app is not upgrade success.

## Failure path

On migration, integrity, approval, or runtime failure, stop sessions and preserve the
backup plus both artifacts. If no forward-only migration ran, use the rollback example. If
release notes declare forward-only state, do not downgrade; follow that release's recovery
procedure.

## Cleanup or off-switch

Retain the previous artifact and backup through the release's rollback window. Remove them
only after qualified operation and the documented retention decision.

## Next

Learn or qualify rollback with
[`../recovery/rollback-exact-release.md`](../recovery/rollback-exact-release.md).
