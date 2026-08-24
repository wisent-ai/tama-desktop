# Capability

What authorizes a supervised session to do something its hooks would
otherwise refuse? A capability: a bounded, session-bound grant record that
the session's runtime holds and Tama can only read. Tama displays
capabilities; it never issues, extends, or revokes one — the
[Session](../desktop/session.md) screen says so on the screen itself.

## What it is

The optional `capability` object inside a session record
(`ai.wisent.tama.session-control.v2`), decoded by the desktop as
`SessionCapability`:

| Field | Meaning |
|---|---|
| `schemaVersion` | Capability schema version |
| `issuedBy` | The issuer identity |
| `nonce` | Uniqueness token for this grant |
| `sessionId`, `controlKey` | The exact session the grant is bound to |
| `releaseId`, `catalogChecksum` | The policy identity the grant was issued against |
| `lifetime` | The declared lifetime class |
| `expiresAt` | Expiry timestamp, when bounded by time |
| `remainingUses` | Use budget, when bounded by count |
| `grants[]` | Per-tool entries: `tool` plus optional `actions[]` |

A grant without `actions` means every action of that tool — the Session
screen renders it as `every action` in the TOOL/ACTIONS table.

## Who requests it

The session, from inside itself. In an OMP session the bundled adapter
(`~/.shared-hooks/omp-shared-hooks.js`) exposes
`tama_request_session_capability`, described in its own tool text as
authorizing "exact tool/action grants for one invocation, a stated
expiration, or the current OMP session". The request is part of the hook
runtime's control plane, not of Tama: the supervisor and its policy decide
whether a grant is issued, and the resulting capability appears in the next
session record Tama polls.

## Who observes it

- The **Session** screen shows the capability of the selected session —
  Lifetime, Expires at, Remaining uses, Issued by, Schema version, Nonce,
  Release, Catalog checksum — with warning tones on identity mismatch, and
  the grants table below ([desktop/session](../desktop/session.md)). A
  session without a capability shows an explicit no-capability message
  rather than an empty table.
- `tama-cli sessions --json` includes the capability in each session's
  record ([cli](../cli.md#read-only-commands)).
- The release/checksum binding is what makes a stale capability visible: a
  grant issued against one [hook release](hook-release.md) does not silently
  carry over to another.

## Where it lives

Only inside the supervisor-owned session record under
`~/Library/Application Support/Tama/session-control/`. It disappears with
the session; nothing durable under Tama's state directory records grants,
and Tama's own state never holds a credential
([what-is-tama](../what-is-tama.md#what-tama-is-not)).

## Not to be confused with

- **A session-scoped enable.** Enabling changes which hooks run
  ([session-enable](session-enable.md)); a capability is an allowance the
  running hooks consult. The Session screen mutates the former and only
  displays the latter.
- **A Wisent role.** `owner`/`admin`/`member` authorize the *operator* to
  use Tama's mutating screens ([desktop](../desktop.md#authorization-tiers));
  a capability authorizes the *agent session* under policy. Different
  subjects, different issuers, different lifetimes.
- **A justification.** Justification-gated hooks demand a recorded human
  reason in a local registry file
  ([hook-model](../hook-model.md#justification-gated-hooks)); a capability
  is a machine-validated grant with nonce, expiry, and use budget. Both are
  evidence, but only the capability is bound to a control key.
