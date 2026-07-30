# Testing and qualification contract

## Current status

The testing stage is **incomplete**. The repository has four deterministic Swift tests,
but no supported preview, current clean-device onboarding evidence, canonical-example
execution record, signed release build result, upgrade/rollback pair, or controlled
credentialed/device/destructive suite. No test or validation command was executed while
creating this document.

A source test pass alone must never be reported as full Tama verification.

## Existing deterministic tests

| Test | Observable contract defended | Plausible defect detected | Current execution status |
|---|---|---|---|
| `JustificationRegistryTests.loadsFileAndTestRequirementsSeparately` | File and test justification requirements load as distinct target kinds with existence/word/expiry state | Requirement kinds collapse or target state is misreported | Not executed in current work |
| `SessionControlClientTests.discoversAndControlsMultipleProviders` | Multiple provider session records are discovered and one scoped override is written/read with expected identity | One provider hides another or override scope/serialization is corrupted | Not executed in current work |
| `ViolationsClientTests.parsesAggregateScanReport` | Aggregate repository, skipped-file, error, and rule-group JSON decodes into visible report totals | Valid scanner output is rejected or totals/groups are lost | Not executed in current work |
| `ViolationsClientTests.parsesCleanReportWithoutViolations` | A valid zero-violation report is represented as clean | Empty successful reports are treated as unreadable or non-clean | Not executed in current work |

These tests use temporary local state and do not prove the signed app, real hook runtime,
privileged backend, process boundary, cleanup provider, or public UI.

## Contract coverage and required evidence

| Product contract | Canonical example | Required proof | Current evidence |
|---|---|---|---|
| Exact artifact and release identity | `examples/operations/verify-release-manifests.md` | Signed/timestamped/notarized artifact; matching digest, provenance, embedded build, dependencies, examples revision, and hook identity | Missing; no preview artifact |
| Clean install to first kernel-gated session | `examples/getting-started/first-kernel-gated-session.md` | Clean supported Mac, real Wisent sign-in, explicit runtime/backend setup, real supervisor, observable ready state | Missing; device and credential qualification required |
| Read-only approved-policy inspection | `examples/core/inspect-approved-policy.md` | Public UI from signed app; no local policy mutation | Missing; safe local example not executed |
| Live session discovery/status | `examples/core/inspect-live-session.md` | Real compatible supervisor plus accepted/stale/invalid records and visible diagnostics | Partial unit evidence only; no execution in current work |
| One-session hook override and scope isolation | `examples/core/control-one-session-hook.md` | Real supervisor accepts valid override and rejects wrong key/session/release/checksum/TTL/capability; second session unchanged | Partial serialization unit evidence only |
| Enable-all transition and reload | `examples/core/enable-all-hooks-one-session.md` | Selected session reloads complete registered set; other sessions unchanged | Missing |
| Emergency disable and transactional restore | `examples/recovery/emergency-disable-and-reenable.md` | Real dispatchers/sessions, forced bounded partial failure, exit-trap resume, backup/manifest, verified re-enable | Missing; destructive qualification required |
| Repository read-only scan | `examples/core/scan-repository.md` | Bundled Node/CLI process against isolated repository; clean and violation reports; tree unchanged; bounded timeout/error | Parser unit evidence only |
| Agent cleanup and final rescan | `examples/core/clean-repository-violations.md` | Isolated recoverable repository, controlled Codex identity, real edits, unchanged HEAD/checked-out branch/local refs, independently inspected remote state, clean final rescan, provider outage/timeout, cancellation that terminates the process tree, preserves partial edits, and rescans | Missing; credentialed provider qualification required |
| Same-version integrity recovery | `examples/recovery/recover-integrity-failure.md` | Corrupt bundle/runtime rejection followed by verified exact-artifact recovery | Missing; controlled fault qualification required |
| Reset/sign-out | `examples/operations/reset-and-sign-out.md` | Welcome/auth state changes while policy installation remains unchanged | Missing |
| Deactivate and uninstall | `examples/operations/deactivate-and-uninstall.md` | Dispatchers disabled, daemon/filter/system extension removed, app removed, unrelated state preserved | Missing; destructive device qualification required |
| Upgrade and rollback | Upgrade/rollback canonical examples | Two exact signed versions, compatible state backup, forward and reverse observable identity/runtime proof, forward-only rejection | Missing; two-version qualification required |
| Integration isolation/outages | Corresponding example failure paths | Wisent Auth, hook bundle, supervisors, macOS backend, Node/CLI, Codex, Apple, and GitHub unavailable independently without corrupting core state | Missing except bounded parser/unit fragments |
| Security and data integrity | All mutation/recovery examples | Auth/confirmation boundaries, repository ownership, per-user modes, atomic writes, immutable releases, no secret serialization, capability expiry/revocation | Missing end-to-end evidence |
| Canonical examples | `examples/README.md` | Every safe local example executed; controlled examples approved and recorded; documented cleanup/failure exercised | All examples honestly marked Draft |

## Required suites

### Swift contract suite

Command, after explicit human test approval:

```bash
swift test
```

Scope: deterministic package tests under `Tests/TamaDesktopTests`. Side effects: SwiftPM
resolution/cache and build artifacts under `.build`. This suite proves only the four tabled
contracts.

### Signed build contract

Command, after explicit approval and with dedicated release credentials:

```bash
TAMA_INSTALL_AFTER_BUILD=no \
WISENT_CODESIGN_IDENTITY='<dedicated identity>' \
WISENT_APP_PROVISIONING_PROFILE='<app profile path>' \
WISENT_NETWORK_FILTER_PROVISIONING_PROFILE='<network profile path>' \
sh Scripts/build-app.sh
```

Scope: app, daemon, System Extension, bundled hook release, manifests, code signing, and
resource layout. Side effects: writes `.build/Tama.app`; it must not install into
`~/Applications`. Qualification additionally inspects signature, entitlements, embedded
versions, dependency revisions, hook provenance, and release resource isolation.

### Safe local canonical examples

Execute every example labeled read-only from its declared clean state using the signed
candidate. Record exact product/source/example/hook identities, expected state shape,
representative failure, and cleanup. File counts or process exit alone are insufficient.

### Clean-device onboarding and core E2E

Use a dedicated Apple-silicon macOS 14+ qualification Mac with no Tama state or credential.
Exercise welcome, Wisent sign-in, explicit runtime install, explicit backend registration,
macOS approval, one real supervisor, session status, scoped override, reload, and normal
cleanup. This suite changes Keychain, Application Support, per-user hook entrypoints,
ServiceManagement, SystemExtensions, NetworkExtension preferences, and Full Disk Access.

### Controlled recovery, provider, and release suites

Separately authorize and execute emergency disable/re-enable, cleanup-agent success/outage/
timeout/cancellation with process-tree termination and partial-edit recovery, integrity
corruption/recovery, deactivate/uninstall, notarized publication, exact upgrade, and
compatible rollback. Use disposable repositories/accounts, dedicated
Apple/GitHub credentials, bounded waits, and exact cleanup. Never target personal or
production state.

## Isolation, determinism, and credential control

- Unit suites own temporary directories and must leave no global Tama state.
- Device suites start from a recorded clean snapshot and use one named release candidate.
- Provider/destructive suites require explicit operator approval for their exact account,
  repository, device, and time window.
- Credentials enter through Keychain, protected profile files, or provider authentication;
  never command arguments, fixtures, logs, screenshots, or evidence.
- Retry occurs only after a classified result proves it is safe. No flaky-test retry policy.
- Cleanup failure fails the suite and remains visible.
- Two Tama versions never share a live Application Support directory concurrently.

## Evidence record

Every executed suite records: suite/example name, exact Git tag and source revision,
artifact digest, hook release ID, platform/architecture, start/end time, controlled
identity label, precondition snapshot, expected observable contract, bounded redacted
result, failure path exercised, cleanup result, and operator approval reference. Release
notes link these records without embedding secrets or personal data.

Testing is complete only when every row above has direct current evidence, all canonical
examples have honest final status, suites are deterministic/isolated/diagnosable, and the
signed published bytes complete clean-device onboarding plus recovery.
