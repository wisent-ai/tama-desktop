# Changelog

All user-visible changes follow the categories required by `docs/releases.md`. A published section maps to the canonical immutable signed Git tag with the same semantic version.

## 0.2.0 — Unreleased

### Added

- Product contract, onboarding, operational, core, integration, example, testing, release, security, and support documentation.
- Explicit welcome and setup flow before any local policy mutation.
- Unauthenticated bundled-policy inspector with no session monitoring or mutation controls.
- Desktop build provenance and immutable release packaging contract.
- Public Tama CLI for portable catalog status, opt-in local runtime-drift checks, namespaced hook operations with atomic registry resealing, provider-declared coverage, Git dispatcher installation, repository workflows, adaptive recovery, and MCP configuration.
- Runnable `examples/` shell commands with inline risk, required-input, side-effect, and rollback comments; CLI link installation is retry-safe, and prose runbooks plus the Markdown coverage matrix were removed.

### Changed

- Runtime installation and macOS policy registration require explicit authenticated confirmation instead of running during model initialization.
- Session discovery is read-only when Tama has not been configured.
- Session monitoring starts only while the authenticated control surface is visible.
- Policy controls now require a current recognized Wisent organization role, and mutation-capable models enforce an explicit construction-time authorization boundary.
- Returning users enter Wisent session restoration; the explicitly selected read-only inspector uses isolated bundled-catalog state.
- In-flight repository scans and cleanup can be stopped; scan cancellation is read-only, while cleanup preserves partial edits and performs the final rescan.
- Runtime-drift CLI checks now resolve Claude and Codex adapter configuration from the current or explicitly selected user home instead of maintainer paths embedded in the signed catalog.
- Local setup and emergency commands now drain output concurrently, enforce bounded output and runtime, and terminate their process tree on timeout.
- Leaving the authenticated control surface cancels active repository scan or cleanup process trees and requires inspection plus a new read-only scan after partial cleanup.
- Product and hook-release identities are displayed separately.

### Fixed

- Session-discovery failures remain visible instead of being represented as an empty successful result.
- Optional violation tooling no longer depends on a hard-coded maintainer directory.
- Nonzero cleanup-agent exits cannot be reported as successful cleanup even when partial edits remove the final violation.
- Hook registration now rejects invalid timeout and registry-path arguments before mutation, reports registry-load, registry-I/O, or mutator-launch failures without an unhandled stack trace, preserves registry permissions across atomic replacement, and retains the primary error if temporary-file cleanup also fails.
- Runtime prerequisites now consistently distinguish local Node.js execution, Python-based installation/restoration, and macOS backend approval across README, onboarding, core, and integration contracts.
- Build, CLI, and runtime installation now reject unsupported Node.js versions; installation validates Node before managed writes, canonicalizes its executable through symlinks, pins that path into installed hook commands and the supervisor launcher, preloads a sealed version guard before every installed target and supervised semantic dispatch, records path and validated version in release provenance, exposes them in Overview, and POSIX-quotes generated shell paths without expansion.
- Release packaging and publication now reject signed `v` tags that are not strict Semantic Versioning, including leading-zero numeric identifiers; publication also verifies the sidecar against the artifact digest, byte size, signed embedded build/hook identities, source revision, dependency pins, channel, and canonical examples before upload.
- Release packaging and publication rejection paths now return failure statuses instead of allowing automation to mistake a printed diagnostic for success.
- Prerelease and build metadata remain in Tama's exact embedded product identity while Apple bundle versions use the required numeric SemVer core; packaging and publication reject drift across the app, Network Extension, tag, manifest, or component build number.
- Channel promotion no longer implies relabeling prerelease bytes as stable: an exact preview remains preview, while a stable SemVer is a distinct signed candidate that must be qualified before one-time publication.
- Packaging and publication accept an explicit `TAMA_RELEASE_TAG` to select one signed release identity when preview and stable candidates share a source commit, reject ambiguous implicit discovery, and reject a selected tag that does not resolve to `HEAD`.
- Publication rejects duplicate ZIP member names, absolute or parent-traversing member paths, and any archive root other than `Tama.app` or optional `__MACOSX` resource-fork metadata before upload.
- Packaging and publication both require the app to pass signature, stapled-ticket, and Gatekeeper assessment; publication repeats those checks from the exact zip before upload.
- Publication now requires an immutable qualification sidecar bound to the exact candidate, complete coverage of each canonical example and required suite kind, repeated identity and cleanup evidence, passed/redacted records, and an asset link injected into release notes.
- Publication requires exactly one matching release-notes section and rejects missing, duplicate, reordered, or empty canonical categories before creating the immutable GitHub release.
- GitHub publication now requires the repository immutable-release policy, creates and retains one stable GitHub release ID, verifies the exact remote signed-tag object, stages exactly the four canonical assets in a private draft, rejects missing or foreign asset names, validates ID, title, tag, notes, draft state, and preview/stable classification, downloads and compares every uploaded byte, rechecks policy immediately before publishing that exact ID with an explicit stable-only `latest` decision, confirms the published metadata and immutable state, redownloads and rechecks the locked asset set, reports the stable ID after failure, and never automatically deletes a GitHub release where draft state cannot be an atomic deletion precondition.
- Remote asset verification now paginates the retained release ID's complete asset collection and downloads every canonical byte stream by its unique release asset ID before and after publication.
- Canonical assets are now uploaded through URLs bound directly to the release ID returned by draft creation; upload and verification no longer resolve a mutable release tag.
- Release publication now classifies preview versus stable from the SemVer prerelease component only, so hyphens inside build metadata cannot suppress a stable release or mark it prerelease.
- App builds now read valid Keychain signing identities once and require an exact certificate-name or case-insensitive hash match, while also rejecting unsupported channel or code-signing timestamp modes and missing app or Network Filter provisioning-profile files before compilation. Build output and optional installation are assembled and signature-checked in private staging directories, then promoted with sibling backups and rollback instead of deleting the previous bundles before fallible work completes.
- Violations command output is retained within explicit bounds and output-limit failures remain visible.
- Cleanup rejects changed HEAD, checked-out branch, or local branch refs and states the remaining external-provider verification boundary.
- Backend status exposes partial installation, and deactivation attempts every privileged component while preserving aggregate failure and restart-required recovery.

### Removed or deprecated

- Automatic service registration on application launch.
- Automatic session-controller installation on application launch.
- Supported-runtime dependence on `~/Documents/CodingProjects/Wisent/hooks-rotator`.

### Security

- Policy-changing setup is moved behind explicit user intent.
- Read-only catalog inspection remains available during Wisent Auth outages without exposing control actions.
- Distributed builds ignore development hook-root and Node executable overrides; unauthenticated inspection does not load local justification or policy state.
- Release artifacts record source provenance and carry independent SHA-256 verification.

### Configuration

- Developer-only source overrides remain unsupported for binary releases.
- Writable cleanup state is kept outside immutable release bytes.

### Data or state migrations

- None. Existing installed hook release and session-control v2 records remain readable.

### Compatibility requirements

- Apple-silicon macOS 14 or newer.
- Python 3 and Node.js 20 or newer for installed runtime and violations workflows.

### Operator actions

- Review setup permissions and explicitly install/register components after upgrading.
- Confirm product build identity and loaded hook release before resuming supervised sessions.

### Known limitations

- No supported preview artifact has been published yet.
- Intel macOS, Linux, and Windows have no supported policy backend.

### Qualification evidence

- Packaging intentionally creates no qualification claim. Publication augments this source-level notice with a link to the completed immutable qualification sidecar for the exact candidate.
