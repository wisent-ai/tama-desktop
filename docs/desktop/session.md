# Session screen

What is one supervised agent session actually allowed to do right now? The
capability document, the tool grants, the loaded release, the liveness
contract, and every recent decision — for the one session selected in the
rail. This is also the only screen that mutates a session, and both of its
mutations point in the enabling direction
([concepts/session-enable](../concepts/session-enable.md)).

## Header and rail

Title `Session`; scope counts live sessions; freshness reads
`updated <time>` from the selected record. Actions: `Refresh sessions`
(secondary) and — only while the selected session does not already have
every catalogued hook enabled — the primary `Enable all hooks`. The facet
rail lists every live session as `<agent> · <project directory>` with its
loaded-hook count and runtime tone; the rail footer names the control
channel: `Application Support/Tama/session-control`. Records are polled once
per second while an authorized operator is signed in; the button re-reads on
demand.

## Faults

Each alert is a distinct failure with its own verbatim title:

- `Session control unavailable` — discovery itself failed; the detail is the
  error sentence, including `Tama found only legacy v1 session records.
  Reinstall the verified bundled runtime, then stop or resume the affected
  agent session to publish v2 state.`
  ([runbook](../runbook.md)).
- `System policy error` — the session record carries a policy error;
  actions are `Approval settings` and, when the record names a support URL,
  `Platform support`.
- `Hook registry failed to load` — the runtime's own registry load error,
  verbatim.
- `The runtime is serving a stale registry` — `reloadRequired` with no
  pending reload; the detail states both identities: `This session loaded
  release <loaded> and the installed release is <installed>. Enabling every
  hook reloads the registry in place.` — with an inline `Enable all hooks`
  action ([runbook](../runbook.md#installed-and-loaded-releases-disagree)).
- `The runtime holds overrides for hooks this build does not declare` — the
  unknown hook ids, listed.

With no live session and no error: `No supervised session is running`, with
the exact expectation — `Tama refuses to start an agent unless the platform
has a ready kernel-enforcement backend. Open or resume a supported
coding-agent session, and it appears here within a second.`

## Hook state per session

One table across every live session before any is selected: SESSION,
GLOBAL STATE (`Enabled` / `Disabled`), LOADED, and ALLOWLIST — `empty` or
the explicit ids during a global disable, otherwise
`all (no overrides)` / `all (<n> disabled)`. This is the desktop's rendering
of the same facts `tama-cli sessions` prints
([walkthrough-runtime-status](../walkthrough-runtime-status.md#1-live-sessions-from-the-sealed-cli)).

## Counters

`Registered` (hooks the runtime knows), `Loaded` (hooks the runtime can
run; warns when it differs from registered), `Overrides` (allowlisted in
this session during a global disable, suppressed otherwise; warns when
nonzero), `Decisions` (semantic events recorded).

## Session capability

The signed authorisation the session holds for privileged tool use
([concepts/capability](../concepts/capability.md)): Lifetime, Expires at
(`Not bounded by time`), Remaining uses (`Not bounded by count`, warning at
one or fewer), Issued by, Schema version, Nonce, Release, Catalog checksum.
Without one: `No capability has been issued to this session. Every
privileged tool call is decided by the standing policy alone.` The grants
table (TOOL / ACTIONS) states the empty cases exactly: `No capability, so
no grants.` and `The capability carries no tool grants; it authorises
nothing by itself.`

## Runtime and decisions

The Runtime box shows Loaded release, Installed release, Catalog checksum,
and Liveness — `heartbeat, <ttl>s TTL` or `process <pid>`, the two modes the
supervisor publishes. During a global disable it adds: `Hooks are globally
disabled on this machine. This session runs only the policies in its
allowlist.` Recent decisions is the register of what policy actually
decided, newest first — WHEN, EVENT, HOOK, DECISION (blocking decisions get
the danger chip; the trailing count is blocks) — with the most recent
blocking `reason` printed verbatim below the table. The same reason headlines
[Posture](posture.md#the-last-blocking-decision).

## Mutations

`Enable all hooks` reports `Enabling every registered hook in session
<id>…` then `<n> hooks enabled in <agent> session <id>.`; the single-hook
enable lives on [Hooks](hooks.md) and reports `<hook-id> is enabled in
<agent> session <id>.` Both travel as private request files the session's
own supervisor validates and applies; rejection
(`The agent runtime rejected the session-control request: <reason>`),
timeout (`The agent runtime did not acknowledge the session-control request
before the deadline.`), and session exit (`The agent session ended before
the session-control request completed.`) are reported failures, never
assumed success.

## Inspector

Selected: Project, Control key (first 12 of 64), Updated at, Policy mode,
Policy backend, Backend capabilities (`None reported` when empty); badges
`Kernel-gated` / `Backend not ready` / `Not configured` plus the capability
lifetime. The screen states its own boundary on the screen: it can *Enable a
hook in one live session* and *Enable every registered hook and reload that
session*; it never can *Disable a hook for one session*, *Issue, extend or
revoke a capability*, or *Read the agent's transcript or tool arguments*.
Unselected, it states the ownership rule: `Session records are written by
the supervised runtime into Application Support and removed when the process
ends. Tama reads them; it never creates one.`
