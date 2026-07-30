# Tama canonical examples

This directory is the canonical catalog of complete user tasks for Tama. It maps the
product promise, public UI and machine interfaces, integrations, lifecycle operations,
recovery paths, and meaningful failures to one bounded example each.

No supported preview is currently published. Every example is therefore marked as a
draft for the first `0.2.x` preview and must not be treated as executed release evidence.
Device-, credential-, and release-infrastructure examples require controlled qualification.

## Risk labels

| Label | Meaning |
|---|---|
| Read-only | Reads the signed app, release metadata, or local status without changing policy |
| Local mutation | Writes Tama-owned per-user state or a selected working tree |
| Security mutation | Changes hook enforcement or session authorization |
| Destructive/recovery | Disables, removes, replaces, or restores managed state |
| Credentialed | Uses Wisent identity, Apple signing/notary credentials, GitHub credentials, or a local cleanup agent |
| Device-level | Requires macOS approval, a System Extension, Network Extension, Full Disk Access, or a live supervisor |
| Provider-facing | Contacts Wisent Auth, Apple notarization, GitHub Releases, or the configured cleanup agent |

## Shared prerequisites

- Apple-silicon Mac running macOS 14 or newer.
- One immutable Tama release and sidecars from an exact GitHub tag. Until a preview is
  published, examples remain drafts and source builds are not substitutes.
- A Wisent account for every policy-changing workflow.
- Node.js 20 or newer and Python 3 only for runtime or violations workflows.
- Administrator approval and Full Disk Access only where a named privileged example says so.
- A stopped, backed-up, or disposable repository before any cleanup example.

Select the row matching one intended outcome, open only its linked example, verify its
status and risk, then follow the sections in order. Do not skip Preconditions, Failure
path, or Cleanup. Never run two Tama versions against the same Application Support state.

## Coverage matrix

| Actor | Outcome | Interface or integration | Preconditions | Risk class | Canonical example | Evidence status |
|---|---|---|---|---|---|---|
| New Wisent developer | Reach one kernel-gated supervised session from a clean Mac | Tama UI; Wisent Auth; hook release; macOS backend; agent supervisor | Exact supported release; account; supported agent | Credentialed, device-level, local mutation | [`getting-started/first-kernel-gated-session.md`](getting-started/first-kernel-gated-session.md) | Draft; clean-device qualification required |
| Developer or security operator | Inspect build identity, catalog, hooks, justifications, validation, and repository-hook mapping | Tama UI; bundled hook release | Exact app artifact | Read-only | [`core/inspect-approved-policy.md`](core/inspect-approved-policy.md) | Draft; safe local execution required |
| Operator | Reveal the exact bundled hook release | Tama UI and Finder | Exact app artifact | Read-only | [`core/inspect-approved-policy.md`](core/inspect-approved-policy.md) | Draft; safe local execution required |
| Operator | Install the integrity-sealed per-user runtime | Tama UI; hook release | Signed in; valid bundle | Credentialed, local mutation | [`getting-started/first-kernel-gated-session.md`](getting-started/first-kernel-gated-session.md) | Draft; controlled-device qualification required |
| Operator | Register and approve the privileged policy backend | Tama UI; ServiceManagement; SystemExtensions; NetworkExtension | Signed helper components; administrator approval | Credentialed, device-level | [`getting-started/first-kernel-gated-session.md`](getting-started/first-kernel-gated-session.md) | Draft; controlled-device qualification required |
| Operator | Inspect one live supervisor and loaded policy state | Tama UI; session-control JSON protocol | One supported live session | Read-only, device-level | [`core/inspect-live-session.md`](core/inspect-live-session.md) | Draft; live-supervisor qualification required |
| Operator | Enable or disable one hook in one live session | Tama UI; session-control JSON protocol | Accepted live session and registered hook | Credentialed, security mutation | [`core/control-one-session-hook.md`](core/control-one-session-hook.md) | Draft; live-supervisor qualification required |
| Operator | Enable every registered hook in one selected session | Tama UI; session-control JSON protocol | Accepted live session | Credentialed, security mutation | [`core/enable-all-hooks-one-session.md`](core/enable-all-hooks-one-session.md) | Draft; live-supervisor qualification required |
| Operator | Emergency-disable every Tama-managed dispatcher and restore it safely | Tama UI; hook release; agent supervisors | Installed runtime; stoppable sessions | Security mutation, destructive/recovery, device-level | [`recovery/emergency-disable-and-reenable.md`](recovery/emergency-disable-and-reenable.md) | Draft; destructive qualification required |
| Repository maintainer | Scan one owned repository without changing it | Tama UI; bundled violations CLI | Existing owned Git repository | Read-only | [`core/scan-repository.md`](core/scan-repository.md) | Draft; safe local execution required |
| Repository maintainer | Ask the declared local cleanup agent to repair violations and prove the final scan is clean | Tama UI; violations CLI; Codex | Recoverable working tree; authenticated Codex | Credentialed, local mutation, provider-facing | [`core/clean-repository-violations.md`](core/clean-repository-violations.md) | Draft; controlled provider execution required |
| Operator | Reset the welcome state or sign out without removing policy | Tama UI; defaults; Wisent Auth | No live override being manually removed | Credentialed, local mutation | [`operations/reset-and-sign-out.md`](operations/reset-and-sign-out.md) | Draft; controlled execution required |
| Operator | Deactivate privileged setup and fully uninstall Tama | Tama UI; macOS services; Finder | All supervised sessions stopped | Destructive/recovery, device-level | [`operations/deactivate-and-uninstall.md`](operations/deactivate-and-uninstall.md) | Draft; destructive qualification required |
| User or automation | Verify an immutable artifact, provenance, product version, source revision, dependency revisions, and hook release identity | Release sidecars and app manifests | Exact GitHub tag and downloaded files | Read-only | [`operations/verify-release-manifests.md`](operations/verify-release-manifests.md) | Draft; safe local execution required after first preview |
| Operator | Upgrade to one exact compatible release | GitHub Releases; Tama UI | Previous identity recorded; sessions stopped; backup when required | Destructive/recovery, device-level | [`operations/upgrade-exact-release.md`](operations/upgrade-exact-release.md) | Draft; two-version qualification required |
| Operator | Roll back to one exact compatible previous release and restore observable state | GitHub Releases; Tama UI; backup | Previous artifact and compatible backup | Destructive/recovery, device-level | [`recovery/rollback-exact-release.md`](recovery/rollback-exact-release.md) | Draft; two-version qualification required |
| Release maintainer | Package, sign, timestamp, optionally notarize, and publish one immutable release | Release scripts; Apple; GitHub | Clean signed tag; release credentials; qualification evidence | Credentialed, provider-facing, destructive | [`operations/package-and-publish-release.md`](operations/package-and-publish-release.md) | Draft; controlled release infrastructure required |
| Supervisor implementation | Read a live session record and consume an atomic override bound to its control key, release, checksum, TTL, and capability | Session-control JSON protocol | Compatible supervisor implementation | Device-level, security boundary | [`core/control-one-session-hook.md`](core/control-one-session-hook.md) | Draft; adapter qualification required |
| Operator | Recover from corrupt bundled catalog or runtime integrity rejection | Tama UI; immutable release artifact | Exact artifact and sidecars retained | Destructive/recovery | [`recovery/recover-integrity-failure.md`](recovery/recover-integrity-failure.md) | Draft; fault qualification required |
| Operator | Diagnose approval-pending backend, absent session, reload-required runtime, or unavailable violations dependency | Tama UI and relevant adapter | A visible classified failure | Read-only or bounded recovery | Failure section of the corresponding example above | Draft; each controlled failure awaits qualification |
| User | Author or approve new hooks | Not supported | — | — | —; see [root README non-goals](../README.md#product-boundaries) | Not supported |
| User | Manage a remote fleet | Not supported | — | — | —; see [root README non-goals](../README.md#product-boundaries) | Not supported |
| User | Commit or push cleanup changes through Tama | Not supported | — | — | —; see [root README non-goals](../README.md#product-boundaries) | Not supported |
| Service | Perform unattended setup or policy mutation | Not supported | — | — | —; see [machine onboarding](../docs/onboarding.md#machine-onboarding) | Not supported |
| User | Share, transfer, import, or export Tama policy state | Not supported | — | — | —; no public contract exists | Not supported |

## Global safety and cleanup rules

- Use exact immutable versions and verify sidecars before opening an artifact.
- Treat every confirmation dialog as a mutation boundary; verify the displayed scope.
- Stop supervised sessions before upgrade, rollback, deactivation, or removal.
- Back up or commit unrelated repository work before cleanup. Tama requests working-tree edits only and rejects detected local Git history/ref mutation; always verify Git and remote state because the provider is external.
- Grant credentials and macOS permissions only to the named component and revoke them when
  the corresponding example says to do so.
- Preserve `~/Library/Application Support/Tama` and emergency backups until recovery is no
  longer required. Never delete managed hook files blindly.
- Record only bounded, redacted evidence. Never copy tokens, Keychain contents, repository
  contents, personal data, Apple credentials, or GitHub credentials into evidence.

## Execution and evidence status

An example may move from **Draft** to **Executed** only after it runs from its declared
clean state through the public boundary and records the expected observable result plus
its cleanup/failure evidence. Safe local examples require explicit test authorization in
the executing session. Credentialed, destructive, provider-facing, release, and
device-level examples additionally require their named controlled environment and
operator approval. No row currently claims executed evidence.

Product contract: [root README](../README.md) · onboarding:
[`docs/onboarding.md`](../docs/onboarding.md) · core:
[`docs/core-contracts.md`](../docs/core-contracts.md) · integrations:
[`docs/integrations.md`](../docs/integrations.md) · operations:
[`docs/operations.md`](../docs/operations.md) · testing contracts:
[`docs/testing.md`](../docs/testing.md)
