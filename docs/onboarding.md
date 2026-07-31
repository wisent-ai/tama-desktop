# Onboarding

## Intended first outcome

A new Wisent developer verifies and opens an exact Tama release, signs in, inspects the bundled policy without changing the machine, explicitly installs local enforcement, and sees one supervised agent session reported as kernel-gated with matching hook release identity.

## Prerequisites

Required for every supported installation:

- Apple-silicon Mac running macOS 14 or newer; check with `uname -m` and `sw_vers -productVersion`;
- a Wisent account with a current `owner`, `admin`, or `member` role in the selected organization; unknown or absent roles cannot open controls;
- access to the private `wisent-ai/tama-desktop` GitHub releases;
- at least 500 MB free local storage; check with `df -h "$HOME"`.

Required for local enforcement or repository scan/cleanup:

- Node.js 20 or newer available on `PATH`, `/opt/homebrew/bin`, `/usr/local/bin`, or `~/.local/bin`.

Required only for local enforcement:

- Python 3 available at `/usr/bin/python3`;
- permission to approve Login Items, a System Extension, Network filtering, and Full Disk Access in macOS settings.

Required only for agent-assisted cleanup:

- an installed and authenticated local `codex` agent;
- a working `git` CLI so Tama can reject HEAD, checked-out branch, or local branch-ref mutation;
- a cleanly recoverable repository working tree owned by the current user.

The release supplies the app, hook catalog, hook runtime, violations CLI, daemon, and Network Extension. A source checkout is never a prerequisite for a supported installation.

## Install an exact release

No supported preview is currently published. Once a preview is marked supported in its release notes:

1. Download the exact zip, digest file, provenance JSON, and release notes from `https://github.com/wisent-ai/tama-desktop/releases/tag/v<SemVer>`.
2. Confirm the provenance `productVersion`, `sourceRevision`, `platform`, and `architecture` match the release and this Mac.
3. In the download directory run:

   ```bash
   shasum -a 256 -c Tama-<version>-macOS-arm64.zip.digest
   ```

   Expected output:

   ```text
   Tama-<version>-macOS-arm64.zip: OK
   ```

4. Expand the zip and move `Tama.app` to `~/Applications/Tama.app`. Elevated privileges are not required.
5. Open the app through Finder. Confirm any Gatekeeper prompt names Tama and the expected Wisent signing identity.

Installation does not register services or modify agent configuration.

## Zero-state and sign-in

The first screen states Tama's purpose, supported environment, identity requirement for controls, and that setup changes are explicit. **Inspect bundled policy** opens an unauthenticated read-only catalog without recording the welcome acknowledgement, starting session monitoring, contacting Wisent Auth, or creating local enforcement state. **Continue to Wisent sign-in** acknowledges the welcome screen and opens authentication.
After the welcome acknowledgement, later launches enter Wisent session restoration rather than opening the inspector implicitly. The inspector remains an explicit toolbar choice and uses an isolated catalog model that does not read installed-policy, backend, session, or repository state.

Enter the Wisent account email and request a one-time code, or use an enabled delegated provider. Credentials and refresh tokens are stored by Wisent Auth in the macOS Keychain. Tama does not store them in Application Support.

If identity is unavailable, the read-only inspector remains usable. Do not install policy through undocumented commands; all runtime, service, session-control, emergency, and repository workflows remain behind authentication and their explicit mutation boundaries.

## First successful workflow

Starting state:

- Tama is installed and signed in;
- no Tama runtime is installed;
- no Tama daemon or Network Extension is registered;
- no supervised agent is running.
- Node.js 20 or newer and `/usr/bin/python3` are available in the documented locations.

Steps:

1. Open **Overview**. Confirm the catalog status is **Valid**, the product version/source revision are displayed, and installed hooks read **Not installed by Tama**.
2. Select **Install local runtime**. After release-integrity validation and before any managed write, Tama resolves Node from the documented locations, rejects versions older than 20, canonicalizes the executable through symlinks, and pins it into every Node-based installed hook command and the generated supervisor launcher. Each installed hook and supervised semantic dispatch preloads the sealed version guard before its target script. Tama also checks the Python installer prerequisite before launch. Review the listed target directories and confirm. Expected result: Overview displays the installed hook release ID, validated Node version and selectable canonical executable path; unrelated agent settings are preserved.
3. Select a catalog hook and open **Session control**. Choose **Register backend**, review the macOS components, and confirm.
4. Approve the daemon/System Extension and Network filter in macOS settings. Grant Full Disk Access only to the named Tama component when prompted.
5. Start one supported supervised coding-agent session using its normal launcher.
6. Return to Tama and choose **Refresh sessions**. Select the new session.
7. Confirm:
   - **Privileged backend: Enabled**;
   - **System policy: Kernel-gated**;
   - loaded and installed release prefixes match;
   - loaded hook count equals registered hook count;
   - no registry error or reload requirement is shown.

That visible status is the first successful product outcome. An exit code or successful login alone is not sufficient.

## Machine onboarding

Tama does not expose an unattended setup or mutation API. Automation may read the
published provenance and hook-release manifests, but a human must verify the artifact,
sign in, confirm runtime installation, and approve every privileged macOS component.
After that setup, supervised agents use versioned capability records in
`ai.wisent.tama.session-control.v2`; each record is bound to a session, control key,
catalog checksum, release ID, lifetime, and remaining-use limit. Missing or expired
capability records fail closed and do not trigger setup automatically.

## Optional repository scan

Open **Violations**, enter an absolute path to a repository owned by the current user, and select **Scan**. The scan is read-only. Select **Stop scan** to cancel its bounded process tree without changing the repository. Success is a report with file counts and either explicit rule violations or zero violations. Scanner errors and skipped files remain visible.

**Clean violations** is separate and mutating. Back up or commit unrelated work first, inspect the confirmation text, and review the resulting working-tree diff, HEAD, checked-out branch, local branch refs, and remote state yourself. Tama does not request commits or pushes and rejects detected local history/ref mutation; the credentialed provider remains an external boundary.

## Common failures

| Failure | Meaning | Corrective action |
|---|---|---|
| Unsupported macOS or architecture | No supported kernel backend exists | Stop; use an Apple-silicon Mac with macOS 14+ |
| Digest mismatch | Download is incomplete or not the immutable release | Delete it and download all files again from the exact tag |
| Sign-in unavailable | Identity configuration, network, or account issue | Preserve existing Keychain state; retry later or contact the repository maintainers with the classified error |
| Python or supported Node missing | Local runtime/violations dependency unavailable; installation has not mutated managed state | Install the required runtime, then retry the explicit action; catalog inspection remains available |
| Backend requires approval | macOS has not authorized the component | Use Tama's settings buttons, approve the exact component, then refresh status |
| Backend removal partial or restart required | One privileged component remains configured or macOS deferred System Extension removal | Stop sessions, restart if requested, reopen Tama, and repeat **Deactivate local setup** until status is `Not registered` |
| Full Disk Access missing | Endpoint Security cannot inspect required paths | Grant access only to the named Tama component and restart the affected session |
| Runtime integrity failure | Bundled or installed hook tree does not match its digest | Reinstall the same verified app artifact; do not edit release directories |
| No active agent sessions | No compatible supervisor record is live, or only a legacy v1 record exists | Install the verified bundled runtime, start or resume a supported session so it publishes v2 state, then refresh |
| Reload required | Session still has an older runtime loaded | If a reload is scheduled, let the active turn settle and refresh; otherwise stop and resume the session after confirming installed release identity |
| Repository path rejected | Path is absent, unsafe, or inaccessible | Select an existing repository owned by the current user |
| Scanner dependency unavailable | Bundled CLI or required local agent is missing | Reinstall the verified app; unrelated core workflows continue |

Errors should say whether retry is safe and name the next action. Preserve only bounded diagnostics and never attach tokens, Keychain records, repository contents, or production logs to an ordinary issue.

## Reset

To show the welcome screen again without touching policy state:

```bash
defaults delete ai.wisent.tama.desktop tama.hasSeenWelcome
```

Sign out from Tama to remove its Wisent session through the normal application flow. Stop supervised sessions before resetting or removing session overrides; never delete live control files while a supervisor can rewrite them.

## Uninstall

1. Stop all supervised agent sessions.
2. In **Overview**, choose **Deactivate local setup** and confirm the operation.
3. Confirm the red disabled banner appears and the privileged backend reports **Not registered**. If macOS still shows an approval item, complete its removal in System Settings before continuing.
4. Sign out and quit Tama.
5. Remove `~/Applications/Tama.app`.
6. Preserve `~/Library/Application Support/Tama` until rollback or incident recovery is no longer needed. It contains disabled-state and restoration evidence, not an active background service.
7. After confirming no managed dispatcher, supervisor, daemon, or Network Extension is active, the authorized operator may archive and remove Tama Application Support and dormant Tama-owned source files named by `hooks-runtime/installed.json`.

## Next steps

After first success:

- start with the read-only commands in [`../examples/getting-started/status.sh`](../examples/getting-started/status.sh), then choose only the script matching the intended operation;
- inspect hook purpose and side effects in **Hook catalog**;
- review expiring justification records;
- scan a repository read-only;
- learn emergency recovery before starting critical agent work;
- read `operations.md` before changing versions or diagnosing partial installation.
