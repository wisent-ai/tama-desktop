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

## CLI example coverage and required evidence

The files under `examples/` are executable command examples, not prose runbooks and not
test evidence. Each script exposes one bounded CLI outcome and states mutation or provider
risk before the command.

| CLI contract | Command example | Required proof | Current evidence |
|---|---|---|---|
| Bundled CLI discovery | `examples/getting-started/install-cli.sh` | Creates or idempotently retains the matching link, refuses unrelated entries, and reports missing PATH configuration | Not executed in current work |
| Catalog health and aggregate provider summary | `examples/getting-started/status.sh` | Stable human output, valid JSON, truthful nonzero status for an invalid catalog, and explicit optional runtime-drift scope | Not executed in current work |
| Hook listing and exact hook inspection | `examples/core/hooks-list.sh` | Human and JSON output agree on ID, source, command, and events | Not executed in current work |
| Hook occurrence registration and removal | `examples/core/hooks-add.sh`, `examples/core/hooks-remove.sh` | Exact event mutation, atomic resealed registry write, validation, and reversible removal | Not executed in current work |
| Provider coverage | `examples/core/provider-coverage.sh` | Provider filtering and complete registry-declared hook/event mappings without claiming live evidence | Not executed in current work |
| Repository read-only scan | `examples/core/scan-repository.sh` | Existing owned repository; clean and violation reports; tree unchanged; bounded error | Parser unit evidence only |
| Provider-backed cleanup and final rescan | `examples/core/clean-repository.sh` | Recoverable repository, bounded agent execution, preserved Git identity, final independent scan | Missing; credentialed provider qualification required |
| User-global Git dispatcher installation | `examples/operations/install-user-git-hooks.sh` | Reviewed plan, exact target writes, Git config result, post-install status | Missing; controlled mutation qualification required |
| MCP configuration | `examples/operations/mcp-config.sh` | Emitted server command resolves to the selected release | Not executed in current work |
| Adaptive recovery triage | `examples/recovery/adaptive-status.sh` | Status, drift, and queue remain read-only; repair/apply stay explicit | Not executed in current work |

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
Qualification must exercise a supported Node executable and confirm that missing or older Node is rejected before build output is replaced. Runtime-install qualification must separately confirm pre-mutation rejection, symlink-resolved canonical executable pinning in both registry command surfaces, one sealed preload path under `hooks-runtime/current` shared by installed commands and supervised semantic dispatch, post-install downgrade rejection before target loading, matching `installed.json.nodeExecutable` and `installed.json.nodeVersion` provenance, the same values in the Overview status, and literal handling of paths containing spaces, apostrophes, dollar signs, and backticks.

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
corruption/recovery, deactivate/uninstall, notarized publication including post-packaging
and pre-upload signature, staple, and Gatekeeper rejection paths, exact upgrade, and
compatible rollback. Use disposable repositories/accounts, dedicated Apple/GitHub
credentials, bounded waits, and exact cleanup. Never target personal or production state.

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
