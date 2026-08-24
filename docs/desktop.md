# Desktop application

The SwiftUI app is the canonical human interface: one window, one sidebar of
destinations grouped by the decision the operator came to make, one screen
at a time. Authorization removes destinations instead of rewriting them — a
signed-out or under-privileged operator sees fewer rows, never dead ones.

## Authorization tiers

- **No credential.** Welcome, sign-in guidance, and the explicit read-only
  inspector: the bundled catalog, its validation, and the declared install
  plan. No session monitoring starts and nothing is mutated.
- **Authenticated with an accepted role.** A current `owner`, `admin`, or
  `member` role in the selected Wisent organization constructs the
  mutation-capable model; unknown or absent roles are denied. Explicit
  confirmation and macOS approval still gate each mutation.

Until guided setup succeeds (`tama.hasCompletedSetup`), an authorized
operator lands in **Set up Tama** — the flow in
[quick-start](quick-start.md). Setup is considered complete only while the
evidence still holds: valid bundled catalog, installed runtime, hooks not
globally disabled, privileged backend `Enabled`, and at least one live
session whose loaded release, checksum, and hook counts match the installed
release with kernel-gated system policy.

## Destinations

| Group | Screen | What is settled there | Control required |
|---|---|---|---|
| Policy | Posture | Release identity, validation, last blocking decision, emergency disable | no |
| Policy | Hooks | The sealed catalog, per-hook detail, reveal source | no |
| Policy | Session | Live sessions, capability, decisions, session-scoped enable | yes |
| Repair | Violations | Read-only repository scan, confirmed cleanup | yes |
| Repair | Justifications | Local justification registries and their expiry | yes |
| System | Coverage | Registry-declared provider/event mappings | no |
| System | Install plan | Where an install would write, per scope level | no |
| System | Settings | Local enforcement state, backend approvals, deactivate, build identity | no |

**Posture** is the headline screen: the desktop product version and source
revision, the hook release the build carries, the release the installed
runtime records, and the release each live runtime loaded — plus the most
recent blocking decision across sessions with its hook id and reason. The
destructive *Disable all hooks* action lives here behind a confirmation
that states exactly what stops working
([enforcement-control](enforcement-control.md)).

**Session** polls live session records once per second while authorized. It
shows each session's runtime status, capability and grants, and every recent
semantic decision. Its only mutations are *Enable a hook in one live
session* and *Enable every registered hook and reload that session*; the
screen itself states that it can never disable a hook or issue, extend, or
revoke a capability.

**Violations** scans the repository chosen in the sidebar's *Repository in
view* — an existing local Git checkout owned by the current user; anything
else is refused before the scanner runs. Scan is read-only and stoppable;
*Repair* is a separate confirmed action that lists what a headless agent
would edit and rescans afterwards ([onboarding](onboarding.md)).

**Settings** shows local enforcement (runtime installed/bypassed, the
privileged backend status with *Approval settings* and *Full Disk Access*
shortcuts) and the build identity, and owns the confirmed
*Deactivate everything* teardown.

## The loopback backend

Reads that belong to the sealed CLI — coverage, install plan, MCP snippet,
violation scan and cleanup — go through one child process the app spawns
lazily: `tama-cli serve --port 0 --root <bundled release>`, which binds
`127.0.0.1` on an ephemeral port, prints a single ready line
`{"ready":true,"port":N}`, and serves `/v1` HTTP endpoints until the app
kills it on quit. Reads are plain GETs (`/v1/coverage`, `/v1/install-plan`,
`/v1/mcp-config`); long-running jobs POST and stream NDJSON
(`/v1/violations/scan`, `/v1/violations/clean`), where `log` events carry
the job's own output and one `result` event carries the exit status and
document. A non-2xx answer is the backend's own refusal sentence in an
`{"error": "…"}` envelope, surfaced verbatim. The full command surface is
[cli](cli.md).

## Privileged backend

**Allow system protection** registers the `ai.wisent.tama.system-policy`
daemon through ServiceManagement and activates the
`ai.wisent.tama.network-filter` System Extension with a socket-filter
configuration. Status is reported as macOS sees it — `Enabled`,
`Requires administrator approval`, `Network filter requires approval`,
`Not registered`, explicit partial-setup states, or a restart-required
message — and approval-pending is never treated as success. Deactivation
attempts filter removal, daemon unregistration, and extension deactivation
independently and reports every failure together.
