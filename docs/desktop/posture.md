# Posture screen

The headline screen: is this machine enforcing the policy it claims, and
what was the last thing policy refused? Posture joins the three release
identities with the live enforcement signals and hosts the machine's most
destructive action. The underlying judgment is
[concepts/posture](../concepts/posture.md).

## Header

Title `Posture`; freshness reads `reading now`, `not read yet`, or
`read <time>`. Actions: `Reveal release` (opens the bundled release in
Finder), `Re-enable all hooks` (only while bypassed), and `Disable all
hooks` (destructive, behind the dialog below).

## Signals and counters

Severity-ordered signal rows: Catalog, Local enforcement, Bundled release,
Managed dispatchers, Local runtime, Privileged backend, Live sessions, Hook
runtime. Hook-runtime tone comes from the shared mapping: `Load failed`
(registry load error), `Reload scheduled`, `Reload required`, else `Loaded`;
loaded-vs-registered count mismatch warns. Counters: `Catalog hooks`,
`Blocking`, `Categories`, `Orphan sources`.

## Release identity

The drift detector, one field per identity
([walkthrough-runtime-status](../walkthrough-runtime-status.md#4-the-identities-the-desktop-compares)):
Product version, Source revision (with `(dirty source)` appended when build
provenance says so), Target, `Bundled release`, `Installed release`,
`Loaded release`, `Catalog checksum`, `Generated at`, `Built`, and — when an
install recorded one — `Node version` and `Node executable`. The honest
placeholders are exact: without control the installed and loaded fields read
`Not inspected`; with control but no installation, `Not installed by Tama`;
with no live session, `No live session`; a runtime that reported no checksum
reads `Not reported by a live session`. Installed and loaded identities that
disagree take the drift warning tone — that disagreement is the screen's
reason to exist.

## Validation

The bundled snapshot's structural validation: ok flag, errors, warnings,
hook and orphan-source counts — with the standing caveat `Bundled snapshot
only: high-entropy and live runtime drift checks are not run in Tama.`
([hook-model](../hook-model.md#the-desktops-catalog-snapshot)). Alert panels
surface `Catalog re-read failed`, `Catalog validation failed`, `All hooks
are disabled`, and `Session control unavailable` states.

## The last blocking decision

The most recent non-allow event across every live session — its hook id and
verbatim `reason` — pulled from the session records' `semanticRuntime`.
This is the answer to "why did my agent stop", one click before the
[Session](session.md) screen's full decision table.

## Disable every Tama hook on this machine

The confirmed dialog states the entire price, verbatim
([concepts/emergency-disable](../concepts/emergency-disable.md#what-it-costs)):
the three body lines about dispatcher bypass, blocking hooks ceasing to
refuse, and surviving per-session overrides; reason code
`hook-emergency-state.v1 disabled=true`; the listing of every blocking hook
id; the footnote `recovery files are preserved under Application
Support/Tama/emergency-backup`; and three actions — `Read the blocking
decision` (jumps to [Session](session.md) when a blocking decision exists),
destructive `Disable all hooks`, primary `Keep policy active`. After the
switch runs, the app re-reads durable state; a switch that did not persist
reports `Tama could not persist the emergency hook state.` rather than
claiming success.
