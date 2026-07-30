# Integration contracts

Integrations extend Tama's local policy-control core. They do not own product state, and an unavailable optional integration must not prevent catalog inspection or emergency recovery.

## Capability summary

| Integration | Capability | Required | Owner | Compatibility |
|---|---|---|---|---|
| Wisent Auth | User and organization identity | Required for mutations | `wisent-desktop-auth` maintainers | Swift package requirement declared in `Package.swift`; a supported release requires a committed resolution and records the exact revision in provenance |
| Hook release | Catalog and local agent/Git adapters | Bundled core data; installation optional | hooks-rotator maintainers | Manifest `ai.wisent.tama.hook-release.v1`; catalog version recorded in release |
| Agent supervisors | Live session status and overrides | Optional until session control | Agent adapter maintainers | Session schema `ai.wisent.tama.session-control.v2` plus capability/runtime sub-schemas |
| macOS policy backend | Kernel/process/network enforcement | Required for supervised-agent readiness | Tama maintainers | macOS 14+, Apple silicon, signed helper identifiers fixed by release |
| Violations CLI | Repository scan and cleanup | Optional | hooks-rotator maintainers | Bundled with exact hook release; app decodes the documented JSON report |
| GitHub Releases | Immutable product artifact distribution | Required for supported installation | Tama release maintainers | Exact `v<SemVer>` tag and artifact digest |
| Local cleanup agent | Mutating violation repair | Optional | Codex operator | The current desktop workflow uses Codex explicitly; no silent provider fallback |

## Wisent Auth

Outcome: authenticate an authorized user and select a Wisent organization before policy mutation.

Data crossing the boundary: email, one-time code or delegated OAuth response, access/refresh tokens, user ID, organization ID/name/role, membership and invitation state. Tokens are sensitive and remain in Keychain/runtime memory. Tama consumes only `WisentIdentity`; it must not log or persist the access token.

Permissions: identity-service access is scoped to the signed-in user and selected organization. Tama admits the current Wisent roles `owner`, `admin`, and `member` to local policy controls and denies unknown or absent roles before constructing mutation-capable models. Organization-management permissions remain owned by Wisent Auth. Rotation and revocation occur through sign-out, token expiry/refresh, identity-provider revocation, or macOS Keychain administration.

Failure behavior: configuration, network, rate-limit, authentication, and service failures remain distinct. A transient restore failure must not erase a valid stored session. Unavailable auth blocks local setup, session monitoring/control, emergency changes, and repository workflows, while the bundled-policy inspector remains available without installing services or corrupting existing policy state.

Lifecycle: built into the app; disabled only by signing out. Leaving the authenticated control surface stops session monitoring and cancels active repository scans or cleanup process trees; partial cleanup edits remain available for inspection and require a new read-only scan. Removing Tama removes the app, while Keychain removal follows sign-out or explicit Keychain administration.

## Bundled hook release

Outcome: provide the exact catalog and runtime approved with the desktop release.

The release contains a schema, content-derived release ID, hook package version, catalog version/update timestamp, and external-source mapping. Install verifies the complete tree digest before mutation. Hook source, registry, and catalog data are untrusted until schema and digest validation succeed.

The app publishes implemented capabilities from the catalog. Missing hooks, duplicate IDs, absent events, unknown IDs, checksum drift, and loaded/installed release mismatch are explicit diagnostics. Unsupported operations fail before override mutation.

Installation is optional for read-only catalog inspection. Disable, re-enable, and removal preserve unrelated agent and Git configuration.

## Agent supervisors

Outcome: expose live sessions and apply exact session-scoped hook overrides.

Supported providers are records that satisfy the shared schema; Tama does not branch core state logic on provider SDK types. Adapter-owned values are translated into `AgentSessionRecord`, normalized runtime status, semantic events, and system-policy status.

Reliability:

- process liveness uses `kill(pid, 0)` and treats `EPERM` as alive;
- heartbeat liveness uses a clamped TTL;
- invalid/stale records are ignored without applying mutations;
- overrides bind to agent ID, session ID, control key, release ID, and checksum;
- atomic writes prevent partial JSON;
- a missing supervisor does not prevent unrelated app startup.

Capabilities outside the schema are unavailable, not emulated.

## macOS policy backend

Outcome: enforce the policy supervisor's process and network decisions through signed privileged components.

Components:

- `ai.wisent.tama.system-policy` LaunchDaemon;
- `ai.wisent.tama.network-filter` System Extension and Network Extension filter;
- Endpoint Security and Full Disk Access privileges where macOS requires them.

Registration occurs only after an authenticated, explicit action. macOS owns administrator approval. The app reports `Not registered`, `Requires administrator approval`, `Network filter requires approval`, `Enabled`, or a classified failure. Unsupported platforms cannot claim readiness and must not fall back to user-space-only enforcement.

Disable/removal unregisters preferences and privileged components before deleting app files. Signing, provisioning, and runtime identity remain separate credentials.

## Violations CLI

Outcome: replay the real bundled pre-write policy against a selected repository and optionally ask one local headless agent to fix reported violations.

Configuration: absolute repository path; cleanup provider; bounded rounds; optional skip fragments. The app invokes the exact CLI bundled with its hook release and passes the bundled hook path explicitly. It does not require `hooks-rotator` source checkout.

Report contract: UTF-8 JSON with repositories, violations, skipped files, scanner errors, problems, and totals. External paths, Git metadata, command output, and agent results are untrusted and bounded before UI display.

Reliability: exit `0` and `1` carry semantic reports; usage rejection and execution failure are distinct. The scanner performs no mutation. Cleanup uses per-repository locking, bounded agent execution, a journal outside immutable release bytes, and a final rescan. Provider absence fails explicitly; Tama never substitutes a different agent.

Lifecycle: bundled with the app; its writable journal and locks live in Application Support and are removed during uninstall.

## GitHub Releases

Outcome: distribute immutable signed artifacts and sidecars from an exact source tag.

Release credentials have repository-content permission only where publication requires it and are unavailable to the app. Publication refuses an existing tag/release. Consumers authenticate to the private repository through their GitHub tooling, download exact filenames, and verify SHA-256 before installation.

An outage prevents download but does not affect installed Tama functionality. Rollback uses previously retained immutable bytes, never a moving `latest` URL.

## Local cleanup agents

Outcome: edit the selected repository working tree to satisfy reported policy rules.

The current desktop workflow supports the detected local Codex executable. Kimi support exists in the underlying CLI but is unavailable through Tama until the UI exposes an explicit provider choice and its contract is qualified. The agent receives repository path, bounded violation metadata, and policy guidance; it does not receive Wisent tokens. Codex runs with its workspace-write sandbox, active hooks, and an instruction not to touch Git history or remotes. Tama requests no commit or push and rejects changed HEAD, checked-out branch, or local branch refs, but the external provider boundary still requires operator inspection of Git and remote state followed by a real rescan.

Timeout, cancellation, nonzero exit, policy-gaming detection, remaining violations, and unavailable executable are distinct results. Cancelling terminates the bundled command, preserves partial working-tree edits, and still triggers the final read-only rescan. Retrying is operator-controlled and bounded. Disabling cleanup leaves scan and every other core workflow available.

## Integration change and removal

Changing a normalized contract follows Tama versioning. Provider-only compatible corrections may be patch changes. Removal requires disabling new calls, revoking credentials/capabilities, stopping jobs, preserving understandable core state, removing adapter files, and documenting any lost capability and migration path in release notes.

Every CLI-exposed integration capability and unavailable-dependency path has a command example in [`../examples/`](../examples/). Scripts declare mutation and provider risk inline; their presence is not executed qualification evidence.
