# Deactivate local setup and fully uninstall Tama

## Goal

Stop Tama enforcement, unregister privileged macOS components, remove the app, and retire
only Tama-owned dormant state while preserving evidence until recovery is no longer needed.

## Status

Draft for the first `0.2.x` preview. Destructive controlled-device execution evidence is
pending.

## Risk

Destructive/recovery, credentialed, and device-level. Removing managed files blindly can
destroy preexisting non-Tama agent settings or restoration evidence.

## Environment

Supported Mac with an installed Tama release, access to System Settings, and every
supervised coding-agent session stopped.

## Preconditions

- Record product and hook release identities, catalog checksum, backend status, and any
  emergency state.
- Save unrelated work and stop all supervisors.
- Preserve `hooks-runtime/installed.json` and emergency backup until final verification.

## Inputs

The UI action applies to the current user's complete local Tama setup. Full removal uses the
installed app location and the exact dormant paths named by the installed manifest; no
wildcard deletion is allowed.

## Artifacts and side effects

**Deactivate local setup** disables managed dispatchers, unregisters the login daemon,
removes Network filter preferences, requests System Extension deactivation, and preserves
restoration evidence. Full removal signs out, deletes the app, and later archives or removes
only confirmed dormant Tama-owned state.

## Steps

1. Stop every supervised agent session.
2. In **Overview**, choose **Deactivate local setup**.
3. Read the destructive confirmation and confirm.
4. Complete any macOS removal approval and refresh status.
5. Confirm the red disabled banner and backend **Not registered**.
6. Sign out through Tama's account UI and quit.
7. Remove `~/Applications/Tama.app`.
8. Preserve `~/Library/Application Support/Tama` until rollback and incident recovery are
   no longer required.
9. Confirm no Tama process, supervisor, daemon, System Extension, Network filter, or managed
   dispatcher remains active.
10. Only then archive or remove dormant Application Support and Tama-owned files named by
    `hooks-runtime/installed.json`.

## Verification

Success requires backend **Not registered**, no active named Tama privileged component,
no active managed dispatcher, no running Tama process, and no app at the installed path.
Preserved emergency/installed manifests must explain any retained dormant files. App
removal alone is not successful uninstall.

## Failure path

If macOS still lists an approval item, complete removal in System Settings before deleting
state. If deactivation fails, keep the app and restoration evidence, leave sessions stopped,
and retry the classified action; never force-delete service files. If a non-Tama setting
shares a managed file, preserve it and follow the manifest restoration contract.

## Cleanup or off-switch

Revoke the qualification Wisent session and remove only the resources proven to be
Tama-owned. Record an explicit retention decision for archived recovery evidence.

## Next

To install again, begin from
[`../getting-started/first-kernel-gated-session.md`](../getting-started/first-kernel-gated-session.md)
with a new exact artifact.
