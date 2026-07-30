# Roll back to one exact compatible Tama release

## Goal

Restore the previous signed Tama artifact and compatible per-user state, then prove one
resumed session loads the previous expected policy without registry or reload errors.

## Status

Draft for the first pair of qualified `0.2.x` previews. Two-version recovery evidence is
pending.

## Risk

Destructive/recovery and device-level. Downgrading across a forward-only migration is
prohibited.

## Environment

Supported Mac after a failed or rejected upgrade, with the exact previous app artifact,
its verified sidecars, and a compatible Application Support backup retained before upgrade.

## Preconditions

- Stop all supervised sessions and quit Tama.
- Read both release notes and prove no forward-only migration ran.
- Verify the previous artifact independently.
- Preserve the failed/new installation and current state as bounded recovery evidence.

## Inputs

The exact previous product version, signed artifact, digest/provenance, and matching backup.
A moving reference, reconstructed app, or backup from another schema line is rejected.

## Artifacts and side effects

Replaces the app and restores the compatible Application Support snapshot. Explicit
re-enable may reinstall the previous app's sealed hook release and restore managed
entrypoints. The procedure changes active policy identity.

## Steps

1. With sessions stopped, move the failed/new app aside.
2. Restore the compatible Application Support backup.
3. Install the exact verified previous `Tama.app`.
4. Open Tama and compare displayed product/source identity with the retained provenance.
5. If the emergency banner or runtime identity requires it, choose **Re-enable all hooks**,
   review the confirmation, and restore the previous app's approved release.
6. Start one supported supervisor, refresh sessions, and select it.

## Verification

The displayed product version/source revision, installed and loaded hook release IDs, and
catalog checksum must equal the recorded previous values. Backend status must be ready,
and the resumed session must have no `reloadRequired`, unknown hooks, or registry error.
Restoring files or receiving command acceptance alone is not rollback success.

## Failure path

If any release declares a forward-only migration, stop and use that release's recovery
procedure. If identities do not match, stop sessions, preserve evidence, and do not mix
artifacts or manually rewrite manifests. If the backend awaits approval, approve only the
named previous signed component and refresh.

## Cleanup or off-switch

Retain both version artifacts and the failed-state evidence until the incident is resolved.
Remove only the replacement files this rollback created when moving forward again.

## Next

After recovery, inspect the loaded state with
[`../core/inspect-live-session.md`](../core/inspect-live-session.md). A later forward move
uses [`../operations/upgrade-exact-release.md`](../operations/upgrade-exact-release.md).
