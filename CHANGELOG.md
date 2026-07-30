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
- Local setup and emergency commands now drain output concurrently, enforce bounded output and runtime, and terminate their process tree on timeout.
- Leaving the authenticated control surface cancels active repository scan or cleanup process trees and requires inspection plus a new read-only scan after partial cleanup.
- Product and hook-release identities are displayed separately.

### Fixed

- Session-discovery failures remain visible instead of being represented as an empty successful result.
- Optional violation tooling no longer depends on a hard-coded maintainer directory.
- Nonzero cleanup-agent exits cannot be reported as successful cleanup even when partial edits remove the final violation.
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

- Pending release qualification; this section must name the executed suites and resulting artifact identities before publication.
