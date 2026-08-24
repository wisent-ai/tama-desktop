# Runbook

Something refused — which sentence are you holding, what does it mean, and
what do you check next? Every heading below is an exact string from this
repository's sources or a state you can reproduce; each entry says where the
sentence comes from, what it is really telling you, and the first read-only
command to run. Attribution tooling is in
[scripts](scripts.md#read-only-integrity-reporters); the executed evidence
for the integrity entries is in the two walkthroughs.

## `Bundled Tama hook release failed its integrity check`

Raised by `install_hook_release.py` before any write, whenever the release
tree no longer digests to its recorded `releaseId`
([concepts/seal](concepts/seal.md#who-enforces-it)). You meet it during a
runtime install, an emergency disable (which installs session controllers),
or a re-enable. The message names no file on purpose — it is a gate, not a
report.

First command:

```bash
python3 Scripts/report_hook_release_integrity.py <release-root>
```

It prints the sealed and actual digests and two attribution lists: files the
digest covers but the installer never installs (build residue such as
Python bytecode — drift, but innocent), and files written after `sealedAt`
(the suspects). A mismatch with *no* newer file is a permission change or a
deletion — the digest covers mode bits
([walkthrough-verify-release](walkthrough-verify-release.md#4-drift-a-permission-bit-and-catch-that-too)).
Never repair a release tree in place: reinstall the same verified app
artifact ([operations](operations.md#failure-and-recovery)).

## `Installed Tama hook release failed its integrity check`

The second, identically worded gate: after the content-addressed copy to
`hooks-runtime/releases/<id>`, that tree must digest to `<id>`. The
installer already deleted and recopied a stale pre-existing tree before
checking, so meeting this sentence means the *fresh copy* failed — a
filesystem-level problem (full disk, interference mid-copy), not stale
state.

First command:

```bash
python3 Scripts/verify_installed_releases.py
```

It digests every installed tree against its directory name, marks `current`,
and answers which of the two identically worded failures an emergency
enable would hit (`second gate: intact` / `second gate: DRIFTED -- install
would refuse`). Executed with both answers in
[walkthrough-runtime-status](walkthrough-runtime-status.md#3-the-state-an-enable-would-refuse).

## Installed and loaded releases disagree

Not an error string — a Posture reading: `Installed release` and `Loaded
release` differ, or the Session screen warns `The runtime is serving a
stale registry`. A live session keeps executing the release it loaded at
start; installing a new one does not restart anybody
([concepts/posture](concepts/posture.md)).

First command:

```bash
tama-cli sessions
```

A lagging session shows a loaded count against a different registered
count, or an old release id in `--json`. The repair is the session-scoped
**Enable all hooks**, which binds an override to the installed release and
checksum and schedules one runtime reload after the active turn settles
([concepts/session-enable](concepts/session-enable.md)). The Session screen
shows the pending state until the transition completes; rejection, timeout
(`The agent runtime did not acknowledge the session-control request before
the deadline.`), or session exit (`The agent session ended before the
session-control request completed.`) is a reported failure, never assumed
success.

## `Tama found only legacy v1 session records. Reinstall the verified bundled runtime, then stop or resume the affected agent session to publish v2 state.`

From `SessionControlClient` when discovery finds no live v2 record but a v1
record exists. v1 records cannot satisfy the v2 `agentId` contract and are
deliberately not migrated ([operations](operations.md#backup-and-restore)).
Do what the sentence says, in that order — the reinstall updates the
supervisor, the stop/resume republishes state.

## Global-disable states

The durable state machine has exactly three observable configurations under
`~/Library/Application Support/Tama`:

| `emergency-backup/manifest.json` | `hook-emergency-state.json` | Meaning |
|---|---|---|
| absent | absent | Enforcing (or never installed) |
| present | present, `disabled: true` | Globally disabled; Tama shows the machine as bypassed |
| one without the other | — | Interrupted transition: treat as disabled and run re-enable, which restores from the manifest and removes both |

The script's own sentences: a repeat disable prints `Tama hooks are already
disabled.`; enable without evidence refuses with `Tama has no emergency
backup manifest to restore.`; success prints `Disabled hooks. Supervised
agent sessions will resume without an editor restart.` or `Enabled approved
hook release <first-12>. Supervised agent sessions will resume without an
editor restart.` The desktop trusts only re-read durable state: `Tama could
not persist the emergency hook state.` means the switch did not stick.
During the bypass, `tama-cli sessions` prints each session's explicit
allowlist (`allowlist: empty` when nothing was re-enabled)
([walkthrough-runtime-status](walkthrough-runtime-status.md#1-live-sessions-from-the-sealed-cli)).

## The installer refuses

Each sentence from `install_hook_release.py`, surfaced verbatim behind
`Tama hook release installation failed: <reason>` (exit 1):

| Sentence | Meaning |
|---|---|
| `Unsupported Tama hook release manifest` | `release.json` schema is not `ai.wisent.tama.hook-release.v1` |
| `Node.js 20 or newer is required; found <versions>` | Node exists on the search path but every candidate is too old |
| `Node.js 20 or newer is required on PATH, /opt/homebrew/bin, /usr/local/bin, or ~/.local/bin` | No usable Node anywhere on the documented search path |
| `Hook registry does not identify its canonical source root` / `…its canonical home` | The registry's `maintainedIn`/`adapters.codex.path` self-references are malformed; path rewriting would be unsafe ([concepts/registry](concepts/registry.md#who-declares-it)) |
| `Unsupported external hook source manifest` | `external-sources.json` schema mismatch |
| `Approved hook source is missing: <id>: <path>` | A catalog hook's source resolves to nothing inside the release |
| `Approved hook release is missing the Node.js runtime preflight` / `…the Tama session supervisor` / `…the universal Tama runtime` / `…the OMP Tama adapter` | A load-bearing runtime file is absent from the release |
| `Full hook installation requires an emergency manifest` | Full install invoked without `--emergency-manifest` (only the emergency path performs full installs) |
| `Approved repository hook is missing: <path>` | The manifest names a moved `.githooks` entry with no approved replacement in the release |
| `Refusing to remove an obsolete path outside managed roots: <path>` | A previous install recorded a source file outside `~/.shared-hooks`, `~/.claude/hooks`, `~/.codex/hooks`, or the managed launchers — the installer aborts rather than delete it |
| `Tama runtime current path is not a symlink: <path>` | Something replaced `hooks-runtime/current` with a real file or directory; remove it manually, nothing else repairs this |
| `Both active and disabled hook entrypoints exist: <path>` | An entrypoint and its `.tama-disabled` sibling both exist; a previous transition was interrupted — decide which is current and remove the other |
| `Missing disabled hook entrypoint: <path>` | The manifest promises a `.tama-disabled` file that is gone |
| `Could not read OMP extensions` / `Could not register OMP hook adapter` | The `omp config` round-trip failed; the transaction rolls back, including a half-applied extensions change |

Every failure rolls the transaction back: originals restored, `current`
re-pointed, the OMP extensions change reverted
([hook-releases](hook-releases.md#installation)).

## The emergency switch refuses

From the desktop wrapper (`HookEmergencySwitch`), each verbatim:

- `The Tama bundle does not contain the emergency hook controller.` — the
  bundled script is missing; the app bundle is incomplete, reinstall the
  verified artifact.
- `The Tama bundle does not contain the agent session-controller installer.`
  / `The Tama bundle does not contain an approved hook release for agent
  session control.` — same class, for the installer and release.
- `The local policy command exceeded its bounded runtime and was
  terminated. Inspect local policy state before retrying.` — the 300 s bound
  fired; the process tree got SIGTERM then SIGKILL. Check the global-disable
  state table above before retrying.
- `The local policy command exceeded Tama's bounded output limit. Inspect
  local policy state before retrying.` — more than 64 KiB of output; same
  inspection.
- `Tama could not read bounded local policy output: <reason>` — the output
  pipe failed; the command's own result is unknown, inspect state.
- `Tama could not update the installed hook configuration.` — the script
  exited non-zero without printing anything.

From the script itself: `Unsupported Tama emergency action: <value>` (exit
2), `Tama session supervisor is missing: <path>` (exit 66), `Tama could not
resume one or more supervised agent sessions.` (the exit trap's resume
failed — sessions may still be paused; resume them via the supervisor).

## `verify` fails inside the desktop release

```console
$ tama-cli verify
tama-require-live-runtime not found next to this binary
```

Captured against the sealed release of 2026-08-24, exit 1: the fixture
runner that `verify` needs is not shipped in the desktop's release. Catalog
validation without fixtures is `tama-cli validate`; hook-behavior fixtures
run in the hook source tree, not from the app bundle.

## The backend refuses a repository

The Violations surface validates before anything runs, each sentence from
`ViolationsClient`:

- `Enter a repository path first.`
- `Choose an existing absolute Git repository directory: <path>` — not
  absolute, not a directory, or no `.git`.
- `Tama refuses to mutate a repository not owned by the current user:
  <path>` — UID mismatch; scanning and cleanup are owner-only.
- `Codex is unavailable. Install and authenticate Codex before confirming
  cleanup.` — repair needs the local headless agent; scan does not.
- `The clean command was cancelled. Partial working-tree edits remain
  visible; inspect them and complete a read-only scan before retrying.`

The loopback backend's own refusals arrive verbatim in `{"error": "…"}`
envelopes — captured live: `{"error":"unknown endpoint: GET /v1/nope"}`
(404), `{"error":"repo not found: /nonexistent"}` (400)
([cli](cli.md#the-desktop-backend)). A backend that cannot start reports
`The Tama backend did not start.` (with stderr detail when there is any) or
`The Tama backend is missing from this build at <path>. Rebuild with
Scripts/build-app.sh.`

## The privileged backend is not `Enabled`

Statuses are macOS's answers, mapped verbatim by
`SystemPolicyServiceManager`: `Requires administrator approval`,
`Network filter requires approval`, `Not registered`,
`Partial setup: daemon enabled; System Extension not installed`,
`Partial setup: <daemon-status>; network policy remains configured`,
`System Extension status unavailable: <error>`, and
`Restart required to finish System Extension activation`. Approval-pending
is never treated as success. The repair is in **Settings**: `Register
privileged backend`, then the macOS `Approval settings` and `Full Disk
Access` shortcuts ([desktop/settings](desktop/settings.md)). Deactivation
failures aggregate as `Tama could not fully deactivate local policy
components: <message>` — each component is attempted independently, so fix
the named one and deactivate again.

## The generated launcher refuses (exit 66)

`~/.local/bin/tama-agent` fails closed before starting a session:
`Tama Node.js runtime preflight is missing: <path>`, `Tama requires its
validated Node.js executable: <path>`, `Tama session supervisor is missing:
<path>`, or `Tama requires Python 3 for the universal session runtime.` The
first two mean the installed runtime under `hooks-runtime/current` moved or
a pinned Node was removed — reinstall the runtime rather than editing the
launcher; the pinning contract is in
[hook-releases](hook-releases.md#installation).
