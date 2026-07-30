# Release and versioning

## Public contract and version policy

Tama uses Semantic Versioning. The exact signed Git tag `v<SemVer>` is the sole canonical version for a distributable desktop release. Release scripts derive the app, Network Extension, artifact, provenance, and release-note version from that tag. Untagged development builds retain source metadata but are never supported or published.

The public contract includes:

- documented UI workflows and their safety confirmations;
- session-control and installed-release JSON schemas;
- Application Support state layout;
- hook-release and build-provenance manifest schemas;
- supported macOS version and architecture;
- setup, emergency recovery, upgrade, rollback, and uninstall behavior;
- integration capability and failure semantics documented in `integrations.md`.

While the major version is zero, an incompatible change advances `MINOR`; a compatible addition or correction advances `PATCH`. Release notes still classify each change as added, changed, fixed, removed, security, configuration, migration, or known limitation.

## Product and hook identities

The desktop product version and bundled hook release are separate identities:

- The exact signed Git tag identifies Tama's public desktop contract.
- The hook `releaseId` is a SHA-256 content identity for the bundled policy tree.
- `tama-build.json` inside the signed app records product version, source commit, channel, build timestamp, target platform, and architecture.
- The published provenance sidecar records the zip filename, byte size, SHA-256 digest, product version, source commit, and build identity.

A release is valid only when every app and extension version equals the tag version, the source checkout is clean, the tag points at `HEAD`, the changelog has a matching release section, code signing succeeds, and the artifact digest matches its sidecar.

## Channels

| Channel | Audience | Guarantee | Promotion and retention | Automatic updates |
|---|---|---|---|---|
| development | Maintainers | May be dirty or unsigned; never supported | Built from branches; not published as a release | Never |
| preview | Authorized Wisent operators | Immutable signed prerelease with qualified core workflows | Exact SemVer prerelease tag; retain while referenced by support incidents or the next preview | Never |
| stable | General intended users | Backward-compatible within a major line and covered by the supported-version window | Exact stable SemVer tag; retain indefinitely | Only after an explicit future update policy |

No stable channel exists yet. The first published artifact must be preview-qualified; promotion reuses the same verified bytes and digest rather than rebuilding.

## Release artifact

Canonical artifact name:

```text
Tama-<version>-macOS-<architecture>.zip
```

Each GitHub Release contains:

- the immutable zip;
- `<artifact>.digest` in `shasum -a 256 -c` format;
- `<artifact>.provenance.json`;
- canonical examples at `https://github.com/wisent-ai/tama-desktop/tree/v<SemVer>/examples`, attributed to the same source revision by provenance;
- user-impact release notes using the format below.

`latest` may be used only as a discovery label. Installation, upgrade, and rollback always select an exact tag, filename, and digest.

## Release process

Owner: the `wisent-ai/tama-desktop` maintainers with access to the dedicated Apple release-signing and GitHub release credentials.

1. Update README first for any changed promise, audience, workflow, interface, environment, or safety boundary.
2. Review downstream onboarding, core, integration, canonical-example, and test contracts.
3. Classify the change, select the next semantic version, and update `CHANGELOG.md`.
4. Review configuration and stored-state compatibility. Add a reversible migration or declare rollback limits.
5. Select a clean commit and create the signed tag `v<SemVer>`.
6. Execute every safe local canonical example in its declared clean state, control and record every credentialed/device/destructive example, then run the suites defined in [`testing.md`](testing.md) in an isolated macOS environment.
7. Run `Scripts/package-release.sh`; it refuses a dirty checkout, wrong tag, conflicting version, absent signing/notary identity, or existing output.
8. Independently validate the signature, stapled notarization ticket, provenance, and SHA-256 sidecar.
9. Publish once with `Scripts/publish-release.sh`; it refuses an existing GitHub release or mismatched tag.
10. Install the published zip on a clean supported Mac, complete onboarding, and record the observed product and hook identities.
11. Promote the exact artifact only after qualification evidence is attached to the release.
12. Preserve the previous supported artifact and recovery instructions.

Build, publication, and runtime credentials are separate. Runtime Wisent credentials are never available to the release scripts.

## Release-note format

Every release note contains these headings, even when the value is `None`:

- Added
- Changed
- Fixed
- Removed or deprecated
- Security
- Configuration
- Data or state migrations
- Compatibility requirements
- Operator actions
- Known limitations
- Qualification evidence

Commit titles alone are not release notes.

## Compatibility and migrations

Tama `0.x` supports only the state schemas documented by that minor line. Unsupported schemas fail before mutation. A migration must define preconditions, backup, duration, restart impact, partial-failure behavior, resume behavior, reversibility, and the compatible rollback version.

Version `0.2.0` introduces no forward-only data migration. It continues to read the existing installed hook release and session-control v2 records. It changes startup behavior: service registration and runtime installation become explicit user actions. This is a breaking onboarding change from `0.1.0`, hence the `0.2.0` version.

Mixed desktop versions must not operate concurrently on one user state directory. Agent supervisors may be resumed only when their loaded hook release and catalog checksum are visible and compatible with the app's bundled catalog.

## Upgrade

1. Record the current Tama version, source revision, installed hook release ID, and catalog checksum.
2. Download an exact newer artifact and sidecars from its immutable GitHub tag.
3. Verify the digest and read migration/operator actions before quitting the old version.
4. Back up `~/Library/Application Support/Tama` when release notes identify a state change.
5. Replace the app while supervised sessions are stopped.
6. Open the new version, confirm build identity, then explicitly install a newer bundled hook runtime if offered.
7. Confirm backend and live runtime status before resuming work.

Skipping intermediate versions is supported only when every skipped release note says its migration is cumulative.

## Rollback

1. Stop supervised sessions and quit Tama.
2. If no forward-only migration ran, restore the exact previous app artifact and its compatible Application Support backup.
3. Open the previous app and re-enable its integrity-sealed hook release if needed.
4. Confirm product version, source revision, hook release ID, catalog checksum, and backend readiness before resuming sessions.
5. If a release declares a forward-only migration, do not downgrade; use its documented recovery procedure instead.

Rollback success is an observable matching build identity plus a loaded runtime without `reloadRequired` or registry errors.
