# Repair reported repository violations with the declared cleanup agent

## Goal

Ask the configured local Codex agent to repair one scanned working tree, then prove the
bundled scanner reports no remaining violations or problems.

## Status

Draft for the first `0.2.x` preview. Controlled provider execution and redacted diff
review evidence are pending.

## Risk

Credentialed, provider-facing local mutation. The agent can edit the selected repository.
Tama requests working-tree edits only, rejects detected local Git history/ref mutation, and requires a final clean rescan. The external provider still requires operator verification of Git and remote state.

## Environment

Supported Tama app, Node.js 20 or newer, installed and authenticated `codex` executable,
and one local Git repository owned by the current user. Use a disposable branch or a
recoverable working tree without unrelated uncommitted work.

## Preconditions

- Complete [`scan-repository.md`](scan-repository.md) and retain its report.
- Back up or commit unrelated work using tools outside Tama.
- Review every reported file and rule; confirm the selected repository is the intended
  mutation boundary.
- Ensure cleanup-agent credentials are scoped and revocable under the agent's own contract.

## Inputs

The repository path is the existing absolute owned Git root already scanned. The current
product exposes Codex as the only cleanup provider and performs no silent fallback.

## Artifacts and side effects

Codex may modify files only inside the selected working tree. Tama stores bounded cleanup
state under its Application Support directory and runs a final scan. Network calls and
provider-side trace retention follow the cleanup agent's contract. Tama requests no commit
or push and fails cleanup if HEAD, the checked-out branch, or local branch refs change.

## Steps

1. In **Violations**, review the current non-clean report.
2. Choose **Clean violations**.
3. Read the confirmation naming the repository and headless agent, then confirm.
4. Wait for the bounded cleanup command and automatic final rescan.
5. Review the final report and command summary.
6. Outside Tama, inspect every working-tree change before accepting it.

## Verification

Success requires the final report to contain zero violations and zero problems. A Codex
zero exit, printed summary, or partial reduction alone is not success. Confirm there is no
commit and no push, and that every changed path lies inside the selected repository.
Record only redacted rule/status evidence, never repository contents or credentials.

## Failure path

Choose **Stop cleanup** to terminate an in-flight agent command. Tama preserves every
partial working-tree edit, performs the final read-only rescan, and reports cancellation
as failure rather than claiming a clean result. Inspect or restore those edits manually.

If Codex is missing, install and authenticate the declared provider before a new explicit
attempt. Timeout, nonzero exit, remaining violations, a locked cleanup, unreadable output,
or failed final rescan is a visible failure. Preserve the diff, stop automatic retries,
and either fix the stated dependency or restore the working tree using the repository's
normal recovery process.

## Cleanup or off-switch

Accept and commit reviewed changes manually outside Tama, or restore only the files changed
by this qualification from the precondition backup. Revoke or sign out the cleanup-agent
credential when it was created only for this task. Run a read-only scan again only under
separate authorized verification.

## Next

Return to [`scan-repository.md`](scan-repository.md) for future read-only checks.
