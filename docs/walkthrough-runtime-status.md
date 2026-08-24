# Walkthrough: inspect runtime status

What is installed, what is loaded, and what would an emergency re-enable hit?
Three read-only answers: the sessions the runtime is supervising right now,
the integrity of every installed release tree, and the second integrity gate
an install would pass through. Every command below was executed on
2026-08-24 against the release sealed as `35204a12…` and a scratch home
(`TAMA_HOME`/`--home` overrides), so nothing operator-owned was touched;
outputs are pasted verbatim with the home abbreviated to `~` and scratch
directories to `$H`. The desktop shows the same facts on
[Posture](desktop/posture.md) and [Session](desktop/session.md).

## 1. Live sessions, from the sealed CLI

`tama-cli sessions` reads the session-control records under
`<home>/Library/Application Support/Tama/session-control/` — the same files
the desktop polls ([enforcement-control](enforcement-control.md#session-records)).
Against a home with no records it prints nothing and exits `0`; `--json`
makes the empty answer explicit:

```console
$ tama-cli sessions --home "$H"
$ tama-cli sessions --json --home "$H"
[]
```

Against the real home of a machine with live supervised sessions, each line
is agent id, session id, and hook state — `loaded/registered` counts for a
normally enforcing session, or the explicit allowlist during a global
disable (excerpt of a longer capture):

```console
$ tama-cli sessions
omp	ReadBatch13	61/61
omp	ReadBatch05	61/61
kimi	session_d62b	?/?
omp	DeepJeden	allowlist: empty
```

Read `61/61` as "61 hooks loaded of 61 registered" — the equality
[Posture](desktop/posture.md) and setup require. `allowlist: empty` is a
session running while hooks are globally disabled: its `enabledHookIds`
allowlist is the only thing that would run, and it is empty
([concepts/session-enable](concepts/session-enable.md)). `?/?` is a session
whose runtime has not reported hook counts.

## 2. Every installed release, verified against its own name

Installed releases are content-addressed: the directory name *is* the
claimed digest, so verification needs no manifest
([hook-releases](hook-releases.md#installation)). On a home where Tama has
never installed anything:

```console
$ TAMA_HOME="$H" python3 Scripts/verify_installed_releases.py
releases root: $H/Library/Application Support/Tama/hooks-runtime/releases exists: False
nothing installed
```

Simulate an installed runtime by copying the sealed release to its
content-addressed landing path and pointing `current` at it — exactly the
layout `install_hook_release.py` produces:

```console
$ TAMA_HOME="$H" python3 Scripts/verify_installed_releases.py
releases root: $H/Library/Application Support/Tama/hooks-runtime/releases exists: True
current: 35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7
  35204a128363 intact <- current
drifted: none

bundled release: ~/Documents/CodingProjects/Wisent/tama-desktop/.build/Tama.app/Contents/Resources/hooks-release exists: True
bundled digest: 35204a128363
second gate: intact
```

Two answers in one report. The top half digests every tree under
`releases/` against its directory name and marks the `current` one. The
bottom half answers the question that matters mid-incident: the emergency
enable path re-installs the bundled release, and its *second* integrity gate
checks `releases/<bundled-id>` — present and intact here, so an enable
cannot fail on it.

## 3. The state an enable would refuse

Change one permission bit inside the installed copy and re-read:

```console
$ chmod 700 "$H/Library/Application Support/Tama/hooks-runtime/releases/35204a…/shared-hooks/registry.json"
$ TAMA_HOME="$H" python3 Scripts/verify_installed_releases.py
releases root: $H/Library/Application Support/Tama/hooks-runtime/releases exists: True
current: 35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7
  35204a128363 DRIFTED <- current
drifted: ['35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7']

bundled release: ~/Documents/CodingProjects/Wisent/tama-desktop/.build/Tama.app/Contents/Resources/hooks-release exists: True
bundled digest: 35204a128363
second gate: DRIFTED -- install would refuse
```

This is the state behind `Installed Tama hook release failed its integrity
check` — the second of the two identically worded installer failures, the
one that is invisible until an operator is already mid-incident
([runbook](runbook.md#installed-tama-hook-release-failed-its-integrity-check)).
The installer's own recovery is automatic for the common case: a
pre-existing copy that no longer digests to its directory name is deleted
and recopied from the bundle before the gate is re-checked
([hook-releases](hook-releases.md#installation)).

## 4. The identities the desktop compares

`installed.json` beside `releases/` records what the last successful install
wrote — release id, catalog checksum, versions, managed files, pinned Node —
and each live session record carries the release id and checksum its runtime
actually loaded. [Posture](desktop/posture.md) calls the machine healthy
only when bundled, installed, and loaded identities agree; this walkthrough
is the command-line version of that comparison, one identity at a time.
