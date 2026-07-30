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

While the major version is zero, an incompatible change advances `MINOR`; a compatible addition or correction advances `PATCH`. Every release-notes section contains exactly these non-empty categories in order: `Added`, `Changed`, `Fixed`, `Removed or deprecated`, `Security`, `Configuration`, `Data or state migrations`, `Compatibility requirements`, `Operator actions`, `Known limitations`, and `Qualification evidence`. Use `None` when a category has no applicable change; never omit it.

## Product and hook identities

The desktop product version and bundled hook release are separate identities:

- The exact signed Git tag identifies Tama's public desktop contract.
- The hook `releaseId` is a SHA-256 content identity for the bundled policy tree.
- `tama-build.json` inside the signed app records product version, source commit, channel, build timestamp, target platform, and architecture.
- `TamaProductVersion` in the app and Network Extension property lists carries the same exact SemVer, including any prerelease or build metadata. Apple's `CFBundleShortVersionString` carries only its three-integer SemVer core, while both components share the same numeric `CFBundleVersion`.
- The published provenance sidecar records the zip filename, byte size, SHA-256 digest, product version, source commit, and build identity.

A release is valid only when its signed tag is strict Semantic Versioning without leading-zero numeric identifiers, each component's `TamaProductVersion` equals that tag version, each Apple bundle version equals the tag's numeric SemVer core, app and Network Extension build numbers are numeric and equal, the source checkout is clean, the tag points at `HEAD`, the changelog has a matching release section, code signing succeeds, and the artifact digest matches its sidecar.

## Channels

| Channel | Audience | Guarantee | Promotion and retention | Automatic updates |
|---|---|---|---|---|
| development | Maintainers | May be dirty or unsigned; never supported | Built from branches; not published as a release | Never |
| preview | Authorized Wisent operators | Immutable signed prerelease with qualified core workflows | Exact SemVer prerelease tag; retain while referenced by support incidents or the next preview | Never |
| stable | General intended users | Backward-compatible within a major line and covered by the supported-version window | Exact stable SemVer tag; retain indefinitely | Only after an explicit future update policy |

No stable channel exists yet. The first published artifact must be preview-qualified. A preview version is never relabeled as stable: a later stable SemVer may reuse the reviewed source revision, but its different exact version requires a distinct signed and notarized artifact. That stable candidate is packaged once, qualified before publication, and then published without rebuilding or replacing its bytes.

Channel classification ignores SemVer build metadata: only a prerelease component between the numeric core and optional `+` metadata selects `preview`. A stable core with build metadata remains stable and may receive the `latest` discovery label; a prerelease remains preview even when it also carries build metadata.

## Release artifact

Canonical artifact name:

```text
Tama-<version>-macOS-<architecture>.zip
```

Each GitHub Release contains:

- the immutable zip;
- `<artifact>.digest` in `shasum -a 256 -c` format;
- `<artifact>.provenance.json`;
- `<artifact>.qualification.json`, bound to the same artifact and containing the completed, redacted qualification record;
- canonical examples at `https://github.com/wisent-ai/tama-desktop/tree/v<SemVer>/examples`, attributed to the same source revision by provenance;
- user-impact release notes using the format below.

`latest` may be used only as a discovery label. Installation, upgrade, and rollback always select an exact tag, filename, and digest.
The matching `CHANGELOG.md` section in the signed tag is the immutable source for release-note content. GitHub keeps a published release's title and body editable even when release immutability is enabled, so the web presentation is checked at publication time but is not a trust anchor.

### Qualification sidecar

The candidate zip exists before qualification so evidence can name the exact bytes it exercised. Qualification writes `<artifact>.qualification.json`; packaging never creates or pre-populates it. The top-level JSON object uses schema `ai.wisent.tama.release-qualification.vOne` and records `productVersion`, `tag`, `sourceRevision`, `artifactName`, `artifactDigest`, `artifactByteSize`, `hookReleaseId`, `platform`, `architecture`, `qualifiedAt`, and a non-empty `records` array.

Every execution record repeats the tag, source revision, artifact digest, hook release ID, platform, and architecture. It also records a unique `kind` and `name`, `status: "passed"`, `redacted: true`, start and end times, controlled identity label, precondition snapshot, expected observable contract, bounded result, exercised failure path, cleanup result, and operator-approval reference. `qualifiedAt` and record times are ISO 8601 values with explicit UTC offsets; a record cannot end before it starts or after qualification completion. Secrets and personal data are prohibited.

Required record kinds are `swift-contracts`, `clean-device-e2e`, and `controlled-recovery-provider-release`. A `canonical-example` record must exist exactly once for every current `examples/**/*.sh` path. Publication rejects missing, duplicate, unsupported, failed, unredacted, incomplete, or candidate-mismatched records; uploads the sidecar with the release; and injects its immutable asset URL under the release-note `Qualification evidence` heading.

## Release process

Owner: the `wisent-ai/tama-desktop` maintainers with access to the dedicated Apple release-signing credentials and a GitHub publication identity that can upload releases and read the repository's immutable-release policy.

1. Update README first for any changed promise, audience, workflow, interface, environment, or safety boundary.
2. Review downstream onboarding, core, integration, canonical-example, and test contracts.
3. Classify the change, select the next semantic version, and update `CHANGELOG.md`.
4. Review configuration and stored-state compatibility. Add a reversible migration or declare rollback limits.
5. Select a clean commit, create the signed tag `v<SemVer>`, and push that exact signed tag object to `wisent-ai/tama-desktop`. When more than one release tag points to that source commit, set `TAMA_RELEASE_TAG` to the exact candidate for both packaging and publication; each script verifies the selected signed tag resolves to `HEAD`, and publication rejects a different remote tag object.
6. Run `Scripts/package-release.sh`; it refuses a dirty checkout, wrong tag, conflicting version, absent signing/notary identity, unsupported build channel or timestamp mode, missing provisioning-profile file, or existing output. Before compiling, the build reads valid Keychain identities once, requires the selected identity to match an exact certificate name or a case-insensitive certificate hash, and validates the channel, timestamp mode, both configured profile paths, and Node. It assembles and verifies the app in a private staging directory; only a complete signed bundle replaces `.build/Tama.app`, with the previous bundle held in a private sibling backup and restored if promotion fails. Optional installation applies the same stage, signature check, backup, promotion, and rollback sequence.
7. Independently inspect the provenance and SHA-256 sidecar against the packaged bytes.
8. Exercise every safe local canonical example from the exact candidate, control and record every credentialed/device/destructive example, then run the suites defined in [`testing.md`](testing.md) in an isolated macOS environment. Write the completed qualification sidecar without rebuilding or modifying the candidate.
9. Publish once with `Scripts/publish-release.sh`; it independently rejects a non-SemVer or mismatched tag, changed source, an existing GitHub release, a remote tag object different from the locally verified signed tag, digest/name/size drift, duplicate, traversal-bearing, or foreign-root ZIP member paths, unreadable or candidate-mismatched provenance and qualification sidecars, missing required suite/example evidence, a missing, duplicate, reordered, or empty release-notes category, dirty or malformed hook identity, unpinned dependencies, channel drift, and canonical-example identity drift. Only `Tama.app` and optional macOS resource-fork metadata under `__MACOSX` may appear at the archive root. Before any GitHub upload it extracts the exact zip into an isolated temporary directory and again requires the app signature, stapled notarization ticket, and Gatekeeper assessment to succeed.

GitHub release immutability must be enabled before publication; the script checks that policy before draft creation and again immediately before making the release public. Publication creates the private draft through the versioned GitHub API and retains the release ID returned by that same create response. It uploads exactly the canonical zip, digest, provenance, and qualification assets without replacement, rejects any missing or foreign asset name, downloads the closed asset set into a fresh directory, and compares each remote file byte-for-byte with its qualified local source. Immediately before publication it addresses that exact release ID and rechecks the ID, remote signed-tag object, draft state, exact tag, title, generated notes body, and preview/stable classification. It publishes by release ID rather than mutable tag lookup and sets GitHub's `latest` discovery label in the same transition only for a stable version; a draft or prerelease is never requested as latest. Afterward it requires the same ID and canonical metadata in non-draft state and GitHub's release record to report `immutable: true`, then redownloads the immutable asset set into another fresh directory and repeats the exact-name and byte comparisons. GitHub locks the published tag and assets and creates the platform release attestation. If the create request fails or its response is uncertain, the script has no returned ID, claims no draft, and deletes nothing; the operator must inspect GitHub and remove only the incomplete matching draft before retrying. After a confirmed create, any later failure inspects and reports the exact returned release ID. Cleanup deliberately never deletes a GitHub release automatically because GitHub offers no atomic delete-only-if-still-draft precondition; an operator must confirm the reported ID remains the incomplete draft before deleting it. If policy visibility, final metadata or immutability confirmation, post-publication byte verification, or ID lookup fails, the command returns failure and requires immediate operator inspection. An administrator could disable the repository policy, or a collaborator could mutate the draft, between the last prepublication checks and GitHub's publication transaction; post-publication metadata and immutable-byte verification detect that external race but cannot make the already-public response atomic.

Remote asset transfer never resolves a mutable release tag. Upload URLs are built from the release ID returned by the create response and URL-encoded canonical asset names. Verification then paginates that retained release ID's asset collection, requires one uploaded asset with a valid asset ID and exact expected size for every canonical name, fetches each byte stream through that asset ID, and repeats the same process after immutability is confirmed.

Every packaging or publication rejection writes an actionable diagnostic, returns a non-zero status, and halts the invoking automation before notarization, output replacement, public release, or support promotion.
10. Install the published zip on a clean supported Mac, complete onboarding, and record the observed product and hook identities.
11. Attach the post-publication clean-install evidence and mark that exact immutable version supported only when it matches the prepublication qualification; never relabel a preview tag or replace its bytes.
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
