# Settings screen

The local installation and the build behind it: install the runtime,
register the privileged backend, and — the screen's one destructive owner —
deactivate everything. Installation is a decision an operator makes once;
it lives here rather than beside the posture verdicts.

## Header

Title `Settings`; scope `inspection mode` when signed out; freshness is the
product version. Actions: with control, `Reveal release` (opens the bundled
release in Finder); without, `Sign in for controls`.

## Local enforcement

Detail sentence, verbatim: `The verified runtime under Application Support,
and the privileged macOS components that gate processes and network
traffic.` Trailing state: `bypassed` / `active`. Fields: `Installed release`
(`Not installed by Tama` before an install), `Privileged backend` (the
macOS-reported status, toned by the shared mapping — `Enabled` success,
`Not registered` neutral, failures and unavailability danger, everything
else warning), and, when an install recorded them, `Node version` and
`Node executable` (`Not recorded`).

Buttons appear only while applicable:

- `Install local runtime` — only without an installed release, enabled only
  while the bundled catalog validates and no mutation is running. Reports
  `Installing the integrity-checked hook runtime…` then
  `Installed hook release <id>.`
- `Register privileged backend`, `Approval settings`, `Full Disk Access` —
  only while the backend is not `Enabled`. Registration reports
  `Registering the privileged macOS policy backend…` and returns macOS's own
  status sentence, including `Restart required to finish System Extension
  activation` ([runbook](../runbook.md#the-privileged-backend-is-not-enabled)).
- `Deactivate` (destructive) — while a release is installed or the backend
  is anything but `Not registered`; it opens the decision dialog below.

The standing footnote: `macOS asks for approval of Tama's daemon, System
Extension, network filter and Full Disk Access where each is required.
Registration is per machine and survives updates.`

## Inspection mode

Signed out, the section states its own boundary — `The sealed catalog and
declared plan remain available. Install and deactivate controls appear when
the managed Tama runtime is available.`, trailing `controls unavailable` —
and lists exactly what `Signing in adds`: live session capability, grants
and decisions; per-session hook enablement; repository violation scan and
repair; the local justification registries; runtime installation and the
privileged backend.

## Build

`What this application is, and which hook release it carries.`, trailing
the channel. Fields: Version, Source revision (with ` (dirty source)`
appended when build provenance says so), Bundled hook release
(`Not recorded` in unsealed development builds), Hook source revision (same
dirty suffix, warning tone), Target (`<platform> · <architecture>`), Built.
The two identities are deliberately separate
([releases](../releases.md)).

## Deactivate local policy enforcement on this machine

The confirmed dialog states the entire price, verbatim:

1. `Every managed hook dispatcher is disabled, so <n> blocking policies
   stops refusing unsafe work.`
2. `Tama unregisters its privileged daemon, System Extension and network
   filter. macOS may require a restart to finish removal.`
3. `Supervised sessions that are running keep running without enforcement.
   Stop them first if that matters.`

Reason code `hook-emergency-state.v1 disabled=true; SMAppService
unregister`; the listing names the four things touched —
`~/Library/Application Support/Tama/hook-emergency-state.json`,
`~/Library/Application Support/Tama/emergency-backup/manifest.json`,
`ai.wisent.tama.system-policy`, `ai.wisent.tama.network-filter` — and the
footnote: `recovery files are preserved; reinstalling verifies the bundled
release before restoring dispatchers`. Actions: destructive `Deactivate
everything`, primary `Keep enforcement`.

Deactivation is the emergency disable *plus* independent unregistration of
the daemon, System Extension, and network filter
([concepts/emergency-disable](../concepts/emergency-disable.md#not-to-be-confused-with));
it reports `Deactivating the local policy setup…` then `Managed dispatchers
disabled. Privileged backend: <status>.`, and component failures aggregate
as `Tama could not fully deactivate local policy components: <message>` —
each component is attempted independently, so fix the named one and
deactivate again.
