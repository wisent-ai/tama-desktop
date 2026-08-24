# Quick start

How do you go from nothing to one supervised agent session whose policy
state Tama can prove? This page is the one happy path: verify an exact
release, open the app, install local enforcement, and watch one session
report matching identities. Full prerequisites, every failure, reset, and
uninstall live in [onboarding](onboarding.md).

Status first: no supported binary has been published yet. These steps are
the contract for the first preview release; source builds
(`Scripts/build-app.sh`) are developer-only and not a substitute for a
supported release.

## Prerequisites

- Apple-silicon Mac, macOS 14 or newer.
- A Wisent account with a current `owner`, `admin`, or `member` role in the
  selected organization — other roles get read-only inspection.
- Node.js 20 or newer on `PATH`, `/opt/homebrew/bin`, `/usr/local/bin`, or
  `~/.local/bin`, and Python 3 at `/usr/bin/python3`, for local enforcement.

## Verify and install the exact release

From the GitHub release tagged `v<SemVer>`, download the zip, its `.digest`
sidecar, and the provenance JSON, then verify before opening anything:

```bash
shasum -a 256 -c Tama-<version>-macOS-arm64.zip.digest
```

Expected output ends with `OK`. Expand the archive and move `Tama.app` to
`~/Applications`. Installation registers no services and modifies no agent
configuration — nothing changes until you explicitly ask.

## Sign in and inspect

Open Tama. Wisent authentication opens directly; credentials go to the
macOS Keychain via Wisent Auth, never into Tama's own state. Without
signing in you can still choose the read-only inspector and see the bundled
catalog, its validation result, and the sealed release identity — that path
starts no session monitoring and mutates nothing.

## Turn enforcement on

After sign-in, guided setup (**Set up Tama**) runs until its evidence is
satisfied:

1. **Turn hooks on** — verifies the bundled release digest, resolves and
   pins a supported Node.js, then transactionally installs the runtime under
   `~/Library/Application Support/Tama` and the managed entrypoints under
   your home ([hook-releases](hook-releases.md)).
2. **Allow system protection** — registers the privileged daemon and
   Network Extension; approve them in macOS settings, and grant Full Disk
   Access only to the named Tama component.
3. Start or resume one supported coding-agent session with its normal
   launcher, then **Refresh sessions**.

Setup completes only when the visible evidence matches: bundled policy
valid, installed and loaded release identities equal, loaded hook count
equal to the nonzero registered count, no disabled or unknown hook ids, no
pending reload, and the system policy reporting **Kernel-gated**. Only the
successful **Open Tama** transition records setup as complete.

## Read the result

The control interface opens on **Posture**: the build identity, the release
it carries, the release the live runtime loaded, and the most recent
blocking decision across sessions — the answer to "why did my agent stop"
([desktop](desktop.md)). From a terminal, the same facts come from the
sealed CLI ([cli](cli.md)):

```bash
~/Applications/Tama.app/Contents/Resources/hooks-release/bin/tama-cli sessions
```

One line per live session with its agent id, session id, and hook state.

That is the whole path. To understand what a hook is, read
[hook-model](hook-model.md); before starting critical agent work, learn the
recovery switch in [enforcement-control](enforcement-control.md).
