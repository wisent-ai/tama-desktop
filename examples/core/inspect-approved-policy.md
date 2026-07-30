# Inspect the approved policy without changing it

## Goal

Identify the exact Tama build and bundled policy, then inspect hooks, justification
requirements, validation, and repository-hook mappings without installing policy.

## Status

Draft for the first `0.2.x` preview. Safe local execution evidence is pending.

## Risk

Read-only. Finder may reveal a directory, but this task does not install runtime state,
register services, change overrides, or contact a cleanup provider.

## Environment

Apple-silicon macOS 14 or newer with one exact verified Tama app. The per-user runtime and
privileged backend may be absent. The catalog is read from the signed app bundle.

## Preconditions

- Verify the app artifact and provenance using
  [`../operations/verify-release-manifests.md`](../operations/verify-release-manifests.md).
- From welcome or the control UI, choose the unauthenticated read-only policy inspector.
- Do not choose any install, register, disable, re-enable, cleanup, or session-change action.

## Inputs

No path, credential, or mutable configuration input is required. Optional search text must
be a hook ID, category, purpose term, or side-effect term shown by Tama.

## Artifacts and side effects

Reads app resources and existing Tama status. **Reveal bundled release** opens Finder.
No managed file or service is created or changed.

## Steps

1. Open Tama and choose **Overview**.
2. Record the displayed product version, source revision, channel, platform, architecture,
   bundled hook release ID, catalog count, blocking-hook count, category count, and
   snapshot validation status.
3. Choose **Hook catalog**. Inspect **All**, **Blocking**, and **Non-blocking** filters and
   search for one displayed hook ID.
4. Select that hook. Read its project, events, purpose, side effects, source path,
   requirements, and enabled-by-default state.
5. Choose **Reveal source** only if a source path is available; confirm Finder opens within
   the bundled release rather than a maintainer checkout.
6. Choose **Justifications** and inspect target, minimum words, expiry, load errors, and
   missing targets without editing source files.
7. Choose **Snapshot validation** and inspect status plus all reported validation errors.
8. Choose **Repository hooks** and inspect each project/event/source mapping.
9. Return to Overview and choose **Reveal bundled release**.

## Verification

Success requires a visible product/source identity, one bundled release ID, a catalog
checksum/count, and a validation result. Every selected hook must have a stable ID and
purpose. Revealed paths must live below `Tama.app/Contents/Resources/hooks-release`.
Installed runtime must remain **Not installed by Tama** when this task began from zero
state.

## Failure path

If the catalog is unavailable or validation is invalid, do not install or repair bundle
contents. Record the bounded error and follow
[`../recovery/recover-integrity-failure.md`](../recovery/recover-integrity-failure.md).
If a justification target is missing, treat the visible error as policy data failure; do
not create a placeholder file.

## Cleanup or off-switch

Close Finder and Tama. No product cleanup is required because this example owns no mutable
state. Sign out only if this was a disposable credentialed qualification account.

## Next

To install enforcement and reach a first result, follow
[`../getting-started/first-kernel-gated-session.md`](../getting-started/first-kernel-gated-session.md).
