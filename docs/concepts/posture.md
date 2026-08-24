# Posture

What single answer does Tama give to "is this machine enforcing the policy
it claims to enforce"? Posture: the joined comparison of three release
identities plus the live enforcement signals, ordered by severity. It is a
derived judgment, not a stored state — nothing on disk says "posture";
every element of it is readable independently.

## What it is

The comparison of three identities that are equal exactly when nothing
drifted:

| Identity | Source | Meaning |
|---|---|---|
| Bundled | `tama-build.json` → `hookRelease.releaseId` | What the signed app carries |
| Installed | `hooks-runtime/installed.json` → `releaseId` | What the last successful install wrote |
| Loaded | session record → `runtime.loadedReleaseId` | What a live session actually executes |

plus the enforcement signals around them: catalog validation, managed
dispatchers (the [emergency-disable](emergency-disable.md) state), the
privileged backend status, live session count, and per-session hook runtime
state (`Loaded` / `Reload required` / `Reload scheduled` / `Load failed`).
Installed and loaded identities that disagree are exactly the drift the
screen exists to surface.

## Who computes it

The desktop's `AppModel`, continuously: it polls session records once per
second while an authorized control surface is open, reads `installed.json`
and the emergency state through `HookEmergencySwitch`, and asks macOS for
the privileged backend status. Two composed judgments matter:

- **setup-ready session** — a live session whose loaded release equals the
  installed release, whose registered hook count equals its loaded count
  with no unknown ids, no pending reload, no registry load error, and whose
  system policy reports kernel-gated mode;
- **setup complete** — bundled catalog valid, runtime installed, hooks not
  globally disabled, privileged backend `Enabled`, and at least one
  setup-ready session ([desktop/setup](../desktop/setup.md)).

## Who displays it

The **Posture** screen is the headline surface
([desktop/posture](../desktop/posture.md)): identity fields (`Bundled
release`, `Installed release`, `Loaded release`, `Catalog checksum`, Node
version/executable), catalog counters, structural validation, the most
recent blocking decision across sessions, and the two opposing actions —
`Disable all hooks` behind its confirmed dialog, `Re-enable all hooks` when
bypassed. Unauthorized inspection shows `Not inspected` for the installed
and loaded fields rather than pretending to know; no live session shows
`No live session`; a runtime that reported no checksum shows `Not reported
by a live session`.

## Reading it from a terminal

The same comparison, one identity at a time — executed end-to-end in
[walkthrough-runtime-status](../walkthrough-runtime-status.md):

```bash
python3 - <<'PY'   # bundled
import json; print(json.load(open("Tama.app/Contents/Resources/tama-build.json"))["hookRelease"]["releaseId"])
PY
cat ~/Library/Application\ Support/Tama/hooks-runtime/installed.json   # installed
tama-cli sessions --json                                               # loaded, per session
```

## Not to be confused with

- **Validation.** Structural validation judges the bundled catalog snapshot
  in isolation (duplicate ids, event-less hooks, unmappable sources);
  posture judges the *relationship* between bundle, installation, and live
  sessions. A valid catalog with a stale loaded release is bad posture.
- **The system policy status.** `Enabled` / `Requires administrator
  approval` / `Not registered` is macOS's answer about the privileged
  backend ([desktop/settings](../desktop/settings.md)); it is one input to
  posture, not the judgment.
- **Coverage.** [Coverage](../desktop/coverage.md) is registry-declared
  provider wiring — what *should* dispatch; posture is what *is* loaded and
  deciding right now.
