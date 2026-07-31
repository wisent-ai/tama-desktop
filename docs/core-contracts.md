# Core contracts

## Stable terminology

- **Product release:** a versioned signed Tama desktop artifact.
- **Hook release:** an integrity-sealed tree of approved policy hooks bundled with a product release.
- **Catalog:** the read-only description of registered hooks and their events.
- **Session record:** supervisor-owned liveness and runtime status for one agent session.
- **Session override:** supervisor-owned hook enablement requested by Tama for exactly one session.
- **Emergency state:** a durable record that all managed dispatchers are bypassed.
- **Policy backend:** the privileged macOS daemon and Network Extension enforcing process and network policy.

## Workflow contracts

### Catalog inspection

Initial state: any app launch, including no account or installed runtime. Input: signed app resources and an explicit choice to inspect. Success: decoded catalog, validation result, hook count, checksum, and build identity are visible without starting session monitoring. Failure: the UI reports an incomplete/corrupt bundle and does not mutate local policy.

The app bundle is authoritative for the displayed catalog. The repository checkout is never authoritative at runtime.

### Runtime installation

Initial state: authenticated authorized operator, valid bundled hook release, documented Node and Python prerequisites available, no operation already running. Input: explicit confirmation. The installer verifies the release digest, resolves and version-checks Node, canonicalizes its executable path through symlinks, and checks Python before any managed write. It then stages release bytes, preserves original files, atomically writes replacements, and atomically changes the `current` symlink. Every installed Node-based registry command names that canonical executable and preloads the sealed runtime version guard before loading its target script; the generated supervisor launcher exports the same executable and guard to its semantic dispatcher. Generated shell assignments use POSIX argument quoting, so supported paths are data rather than shell expansion.

Success: `installed.json` records schema, release ID, checksum, hook package version, catalog version, timestamp, previous release ID, managed files, and the pinned Node executable plus its validated version. Failure: original files and symlink are restored; prerequisite failures occur before managed mutation. Retrying is safe after the previous transaction has completed.

Concurrent installation is rejected by the UI operation state and filesystem transaction ownership. Two Tama processes must not mutate one user's installation concurrently.

### Backend registration

Initial state: authenticated authorized operator; signed helper components present. Input: explicit confirmation. Success requires registered daemon status and enabled Network Extension preferences. Approval-pending is a distinct visible state, not success. Failure leaves session-control requests unavailable but does not corrupt hook state.

Deactivation disables managed dispatchers, then independently attempts Network filter preference removal, daemon unregistration, and System Extension deactivation so one failure does not skip later cleanup. Partial state and restart-required removal remain visible and retryable; `Not registered` is reported only when no managed backend configuration remains detectable.

### Session discovery

Session files have schema `ai.wisent.tama.session-control.v2`. A record is accepted only when its schema, lowercase agent ID, 64-character hexadecimal control key, liveness mode, and TTL/process liveness are valid. Invalid or stale records are ignored. When no live v2 record exists but a legacy v1 record is present, discovery reports the required runtime reinstall and session restart instead of presenting an unexplained empty result. Discovery is read-only when the control directory does not exist.

### Session override

Input: authenticated user confirmation, live accepted session, and a nonempty registered hook ID to enable. Tama submits a private request bound to the session ID and control key. The agent supervisor validates that envelope, writes `<controlKey>.override.json` atomically with mode `0600`, and returns the authoritative resulting session. The override carries agent ID, session ID, control key, release/checksum binding, disabled/enabled hook IDs, retained capability, and update timestamp.

An override matches only the exact session identity tuple. During global emergency disable, enabled IDs form the session allowlist. Agent-session controls never disable a hook; disabling enforcement remains an operator-owned global emergency action outside the agent session. Retrying the same enable request is idempotent. A vanished or changed session fails before a successful UI state is claimed.

A session-wide enable-all request first persists an override bound to the installed release and catalog checksum, then schedules one native OMP reload after the active tool callback and agent turn settle. Concurrent reload requests coalesce; enable-all arriving behind a plain pending reload upgrades the persisted intent before that same reload executes. A scheduling, intent-upgrade, or reload failure restores the applicable preceding override state; the session record exposes the pending state until the runtime transition completes.

The desktop writes a private, session-keyed `set-hook` or `enable-all` request and waits for the matching runtime response. It updates the visible session only from that authoritative response; rejection, malformed identity, session exit, or timeout is an actionable failure rather than optimistic success.

### Emergency disable and re-enable

Disable requires explicit destructive confirmation. Supervised sessions pause before dispatcher mutation and resume through an exit trap. Original configuration and moved entrypoints are recorded once in an emergency manifest. Repeated disable is idempotent.

Re-enable requires the manifest and a valid bundled release. Installation is transactional. Success removes emergency state only after managed configuration is restored. Failure preserves recovery evidence and does not claim enabled state.

### Violation scan and cleanup

Scan accepts an existing local repository path and invokes the bundled production scanner. Scan is read-only and reports semantic success separately from process exit status: exit `0` means no violations, `1` means a valid report with violations/problems, `2` is rejected usage, and other statuses are execution failure. The operator can stop an in-flight scan; Tama terminates its process tree and reports cancellation without changing the repository.

Cleanup requires a preceding report with violations and separate confirmation. The selected local agent receives only the chosen working tree as its mutation boundary. Tama requests no commit or push, rejects changed HEAD, checked-out branch, or local branch refs, and rescans before showing completion. The provider remains an external credentialed boundary, so the operator verifies Git and remote state. Agent success without a clean observable report is not product success. Cancellation leaves working-tree changes visible for manual recovery.

## State transitions

```text
Local runtime: absent -> installing -> installed
                         | failure -> absent/previous installed

Policy backend: not registered -> approval required -> enabled
                                  | failure -> not registered/approval required

Global hooks: enabled -> disabling -> disabled -> enabling -> enabled
                          | failure -> previous durable state

Session override: observed -> writing -> applied
                               | failure/stale session -> observed + actionable error
Session reload: observed -> persisted override -> scheduled -> loaded
                                                | failure -> previous durable state

Violation job: idle -> scanning -> report
                      | failure -> diagnostic
report with violations -> cleaning -> rescanning -> clean report | remaining report | failure
```

Transition state is never inferred solely from a button click or child-process exit. The durable state or final report is reread before success is shown.

## Failure taxonomy

Public errors distinguish:

- invalid input or unsupported path;
- missing prerequisite;
- authentication or authorization failure;
- unavailable bundled component;
- unavailable external dependency;
- integrity or compatibility mismatch;
- approval required;
- stale or conflicting session;
- retryable process/transport failure;
- permanent execution failure;
- partial completion requiring inspection;
- cancellation or timeout.

Every error includes the failed operation, whether retry is safe, and one corrective action. Raw stack traces, access tokens, capability material, and unbounded child output are prohibited.

## Safety and authorization

- Welcome, sign-in guidance, and bundled-policy inspection require no credential. Wisent authentication plus a current selected-organization role of `owner`, `admin`, or `member` gates construction of mutation-capable models; unknown or absent roles are denied. Additional explicit confirmation and macOS approval protect mutations.
- The macOS user owns per-user session and runtime state. Privileged registration is delegated to macOS approval.
- Every mutating UI action names its scope and requires confirmation when it changes system policy, all hooks, or repository files.
- Paths supplied to repository workflows must exist, resolve to a directory, and be owned by the current user before mutation.
- Secrets stay in Keychain or supervisor capability boundaries and are never serialized into Tama state.
- Installed releases are content-addressed; unknown files outside managed roots are never removed.
- Emergency disable is the recovery control for hook-induced loss of availability.

## CLI policy surface

`tama status` validates the immutable catalog without treating absent local provider
configuration as catalog corruption. `tama status --runtime` additionally checks Claude
and Codex installation drift at `~/.claude/settings.json` and `~/.codex/hooks.json` for
the current user. `--home <path>` selects a different explicit home. JSON output states
both `runtimeInstallChecked` and the resolved `runtimeHome`, so automation cannot confuse
catalog scope with local-runtime scope. `tama provider coverage` reports registry-declared
hook/event mappings only and explicitly does not claim live execution.

Hook inspection is read-only. `tama hooks add` and `tama hooks remove` are maintainer
operations: both require an explicit writable `--root`, refuse implicit signed bundles or
installed releases, keep one command identity per hook ID, preserve occurrences on other
events, write the complete resealed registry atomically, and expose an exact rollback
command in the corresponding example. Missing option values are usage errors. Hook
timeouts must be integer seconds in the inclusive range 1–3600; invalid values are
rejected before the registry is written.
Registry read, parse, temporary-write, and rename failures produce a bounded diagnostic and a nonzero exit without exposing a stack trace. Replacement preserves the existing registry file permissions and becomes visible through one same-directory atomic rename; failed temporary-file cleanup never masks the primary write failure.

## Observability and bounds

Primary operations expose requested scope, current state, final result, failure class, and required action. Child-process output is drained concurrently and bounded before display. Local setup and emergency commands have a bounded runtime and terminate their process tree on timeout. Polling uses one task per authorized control model and stops when that control surface disappears. Session TTL is clamped to 5–3600 seconds. Repository cleanup agents have a bounded execution time defined by the bundled CLI.

The app does not promise a repository size or scan latency until measured release qualification establishes one. It processes scans asynchronously so the UI remains responsive. Disk growth is bounded by explicitly installed hook releases, state journals, and session records; uninstall and release-retention procedures remove obsolete state.

## Evolution

Schema changes follow the version policy in `releases.md`. Readers reject unsupported schema roots before mutation. Clean migrations replace old representations; permanent aliases and silent cross-provider fallbacks are prohibited. Integration types are translated at the adapter boundary and do not become the shared product vocabulary.

Every public CLI outcome has a directly runnable command example in [`../examples/`](../examples/). A contract change updates the affected script before tests.
