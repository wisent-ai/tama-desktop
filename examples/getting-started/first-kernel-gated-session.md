# Reach the first kernel-gated supervised session

## Goal

Install one exact Tama preview from a clean Mac and observe one supported coding-agent
session as kernel-gated with matching hook-release identity.

## Status

Draft for the first `0.2.x` preview. No supported binary exists yet; controlled clean-device
execution and redacted evidence are pending.

## Risk

Credentialed, local mutation, provider-facing, and device-level. This task installs
per-user hook entrypoints and requests approval for privileged macOS components.

## Environment

Apple-silicon Mac running macOS 14 or newer, Finder, System Settings, network access to
Wisent Auth, and one supported local coding-agent supervisor. Begin with no Tama app,
Application Support state, credentials, runtime, daemon, Network Extension, or live agent.

## Preconditions

- Exact preview zip, `.digest`, provenance JSON, and release notes from one immutable tag.
- A Wisent account authorized for local policy changes.
- Node.js 20 or newer and Python 3.
- Permission to approve the named Tama daemon, System Extension, Network filter, and Full
  Disk Access where macOS requires them.

## Inputs

Set `ARTIFACT` to the downloaded zip filename. It must match
`Tama-<version>-macOS-arm64.zip`; `<version>` must equal the immutable release tag and
provenance `productVersion`.

## Artifacts and side effects

Creates `~/Applications/Tama.app`, Wisent credentials in Keychain, Tama state under
`~/Library/Application Support/Tama`, managed per-user hook entrypoints, a registered
login daemon, System Extension, and Network filter preferences. It does not create a
repository commit or remote resource.

## Steps

1. In the download directory, verify the exact sidecar:
   ```bash
   shasum -a 256 -c "$ARTIFACT.digest"
   ```
2. Open the provenance JSON and confirm `artifactName`, `productVersion`,
   `sourceRevision`, `sourceDirty: false`, `platform: macOS`, `architecture: arm64`, and
   nonempty dependency revisions match the release.
3. Expand the zip, move `Tama.app` to `~/Applications`, and open it through Finder.
4. Read the welcome screen and choose **Continue to sign in**. Confirm no install or
   approval prompt appeared merely from displaying guidance.
5. Complete Wisent sign-in. Open **Overview** and confirm catalog status **Valid**, a
   product version/source revision, and **Not installed by Tama**.
6. Choose **Install local runtime**, review the target directories, and confirm.
7. Confirm Overview displays the installed hook release ID matching the bundled release.
8. Open **Session control**, choose **Register backend**, review the component list, and
   confirm. Approve only the named Tama items in System Settings.
9. Start one supported supervised coding-agent session using its normal launcher.
10. Return to Tama, choose **Refresh sessions**, and select that session.

## Verification

The selected session must show **Privileged backend: Enabled** and **System policy:
Kernel-gated**. Loaded and installed release prefixes must match, loaded hook count must
equal registered hook count, and neither a registry error nor **Reload required** may be
visible. Login or process exit alone is not success.

Evidence to record after authorization: release tag, product/source identity, hook release
prefix, catalog checksum prefix, status labels, and cleanup result. Redact account and
project identifiers.

## Failure path

If the backend shows **Requires approval**, use Tama's settings action and approve the
exact component, then refresh. If the runtime identity mismatches or reports an integrity
failure, stop; reinstall the same verified artifact and do not edit release directories.
If no session appears, start or resume a supported supervisor and refresh instead of
creating session files manually.

## Cleanup or off-switch

Stop the supervised session. For a disposable qualification Mac, follow
[`../operations/deactivate-and-uninstall.md`](../operations/deactivate-and-uninstall.md).
For a retained installation, leave the verified runtime and approved backend in place and
record that retention decision.

## Next

Inspect the exact loaded session with
[`../core/inspect-live-session.md`](../core/inspect-live-session.md), then learn emergency
recovery in
[`../recovery/emergency-disable-and-reenable.md`](../recovery/emergency-disable-and-reenable.md).
