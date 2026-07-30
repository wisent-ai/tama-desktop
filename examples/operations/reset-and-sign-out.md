# Reset welcome state or sign out without removing policy

## Goal

Return Tama to welcome or signed-out state while deliberately retaining installed policy
and privileged components.

## Status

Draft for the first `0.2.x` preview. Controlled credential and local-state evidence are
pending.

## Risk

Credentialed local mutation. Sign-out removes the Wisent session from Keychain; neither
operation disables installed enforcement.

## Environment

Supported Tama installation on macOS with no session override file being manually removed
and no setup/uninstall operation running.

## Preconditions

- Record whether local runtime and backend are installed.
- Stop supervised sessions before resetting any session-specific state.
- Know that this is not uninstall and does not deactivate policy.

## Inputs

Choose exactly one outcome: reset only the welcome acknowledgement, or sign out through the
account UI. The bundle identifier is fixed by the product release.

## Artifacts and side effects

Welcome reset removes only the `tama.hasSeenWelcome` preference. Sign-out removes the
current Wisent session through Wisent Auth/Keychain. Installed runtime, daemon, Network
Extension, emergency state, and unrelated agent configuration remain unchanged.

## Steps

For welcome reset:

1. Quit Tama.
2. Run:
   ```bash
   defaults delete ai.wisent.tama.desktop tama.hasSeenWelcome
   ```
3. Reopen Tama and stop at the welcome screen.

For sign-out:

1. Stop supervised sessions when their UI state is being inspected.
2. Use Tama's account toolbar and choose **Sign Out**.
3. Leave installed policy untouched unless the separate uninstall outcome is intended.

## Verification

Welcome reset succeeds only when Tama displays its welcome guidance again and does not
request privileged setup merely from displaying it. Sign-out succeeds only when the auth
UI replaces the signed-in product UI and the Wisent session is no longer presented.
Previously recorded runtime/backend status must not be represented as removed by either
operation.

## Failure path

If `defaults` reports the key is absent, the welcome state is already reset; reopen Tama.
If sign-out fails, retain Keychain evidence, do not delete arbitrary credentials, and use
the classified Wisent Auth recovery path. If policy removal was intended, stop and use the
separate deactivation example.

## Cleanup or off-switch

Complete sign-in again if the retained installation will be used, or leave it signed out as
the explicit result. Remove the installation only through
[`deactivate-and-uninstall.md`](deactivate-and-uninstall.md).

## Next

Use [`deactivate-and-uninstall.md`](deactivate-and-uninstall.md) for full removal.
