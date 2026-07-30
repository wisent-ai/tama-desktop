# Tama operational model

## Ownership and trust boundaries

| Resource | Authority | Writer | Retention and removal |
|---|---|---|---|
| Signed `Tama.app` | Published release artifact | Release operator | Replace only through an explicit upgrade; remove with the app |
| Bundled catalog | Signed app bundle | Release build | Immutable for the life of that app version |
| Installed hook release | `~/Library/Application Support/Tama/hooks-runtime/releases/<release-id>` | Tama installer | Retained while referenced by `current` or `installed.json`; remove during uninstall |
| Current hook release | `hooks-runtime/current` symlink | Tama installer transaction | Atomically replaced; previous ID recorded in `installed.json` |
| Emergency state | `hook-emergency-state.json` and `emergency-backup/` | Emergency controller | Removed only after successful re-enable or explicit uninstall |
| Session records | `session-control/*.session.json` | Agent supervisor | Stale records are ignored and removed; directory mode `0700` |
| Session overrides | `session-control/*.override.json` | Tama | Atomic files, mode `0600`; removed during reset/uninstall |
| Wisent session | macOS Keychain | Wisent Auth | Removed by sign-out or Keychain administration |
| Privileged daemon and filter preferences | macOS ServiceManagement and NetworkExtension | Explicit setup action | Removed by the uninstall procedure |

No log, cache, or UI snapshot is authoritative policy state. Hook catalog checksum and release ID are the evidence used to compare the signed bundle, installed release, and live runtime.

## Configuration

Tama has no required environment variables for a supported binary installation. Maintainer-only overrides are:

| Variable | Purpose | Safety rule |
|---|---|---|
| `TAMA_HOOK_ROOT` | Select the hook source during a maintainer build | The path is not retained; runtime source override is compiled out of distributed builds |
| `TAMA_INSTALL_APP_PATH` | Select developer installation destination | Must not be used by the release workflow |
| `TAMA_NODE` | Select Node.js for maintainer catalog export or a debug runtime | Runtime override is compiled out of distributed builds; the executable must be Node.js 20 or newer |
| `WISENT_CODESIGN_IDENTITY` | Select signing identity | Release credentials stay separate from runtime identity |
| `WISENT_APP_PROVISIONING_PROFILE` | App provisioning profile | Release operator only |
| `WISENT_NETWORK_FILTER_PROVISIONING_PROFILE` | Network Extension profile | Release operator only |
| `WISENT_NOTARY_PROFILE` | Keychain profile used by Apple notarytool | Required for every published preview or stable release; never available at runtime |
| `TAMA_TEST_IDENTITY` | Automated UI-test identity seam | Prohibited in distributed artifacts and ordinary use |

Unknown UI configuration is rejected by construction: setup choices are explicit actions rather than free-form settings. Integration-specific configuration is documented in `integrations.md`.

## Permissions

- Ordinary catalog inspection requires only read access to the app bundle and the user's Application Support directory.
- Installing the per-user runtime writes to `~/.shared-hooks`, `~/.claude/hooks`, `~/.codex/hooks`, `~/.local/bin`, Git hook locations recorded by the catalog, and `~/Library/Application Support/Tama`.
- Registering the policy backend requests macOS approval for a privileged daemon, System Extension, Network Extension configuration, and Full Disk Access where required.
- Repository scan is read-only. Cleanup requires write access to the selected working tree and launches the explicitly selected local agent.
- Tama never requires an administrator credential for catalog inspection or per-user session override files.

## Observability

The Overview and Session control views expose:

- desktop product version and source revision;
- bundled and installed hook release IDs;
- catalog checksum and registered/loaded hook counts;
- daemon and kernel-policy readiness;
- active agent identity, session ID, project path, and liveness mode;
- semantic event sequence and last event;
- unknown hooks, reload requirement, and backend diagnostics;
- violation scan totals, skipped files, and per-file errors.

Diagnostics must identify remediation without including access tokens, raw external payloads, or repository file contents beyond paths and rule messages.

## Failure and recovery

- **Catalog unavailable:** the signed bundle is incomplete. Reinstall the same immutable app artifact and verify its digest.
- **Runtime integrity failure:** installation stops before changing the active symlink. Reinstall from the signed app; do not edit files inside a release directory.
- **Partial runtime installation:** the transaction restores original files and previous `current` symlink.
- **Backend approval pending:** open the displayed macOS settings destination, approve the component, then refresh status.
- **Agent session unavailable:** the operation does not write an override. Restart the supervised session and select its new session record.
- **Emergency disable partially fails:** sessions are resumed by the exit trap; preserve `emergency-backup` and retry re-enable from the same app version.
- **Violation dependency unavailable:** scanning or cleanup fails independently; catalog inspection and session control remain available.

Never repair `installed.json`, `current`, or emergency manifests manually as a normal recovery procedure.

## Backup and restore

Before an upgrade that changes stored-state schemas, back up `~/Library/Application Support/Tama`. Version `0.2.0` uses versioned JSON schemas and does not require a migration from `0.1.0`; the installer preserves prior hook release identity.

To restore after a failed compatible upgrade:

1. Quit Tama and stop supervised sessions.
2. Restore the Application Support backup.
3. Restore the exact prior signed `Tama.app` artifact and verify its digest.
4. Open Tama, confirm the product and hook release IDs, then resume agent sessions.

Do not run two Tama versions against the same Application Support directory concurrently.

## Reset and uninstall

A reset removes Tama-owned welcome or stopped-session override state without unregistering privileged components or deleting unrelated agent configuration. **Deactivate local setup** disables managed dispatchers and unregisters the daemon and Network Extension while deliberately preserving restoration evidence. Full removal then signs out, removes the app, confirms no Tama process or dispatcher remains active, and archives or removes dormant files named by the installed manifest.

Use the versioned procedure in `onboarding.md`; do not delete managed hook files blindly because existing non-Tama settings and dispatchers may need restoration.

Canonical bounded tasks for backup-sensitive operations, upgrade, rollback, emergency recovery, reset, and removal are indexed in [`../examples/README.md`](../examples/README.md).
