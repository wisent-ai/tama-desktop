# Violations screen

Findings in the repository under repair, and the one irreversible verb.
Scan is read-only and replays the release's real pre-write hook; *Repair*
hands the working tree to one headless external agent behind a confirmed
dialog and trusts only the final rescan. The engine is the sealed CLI's
`find-violations` / `clean` ([cli](../cli.md#repository-scans-and-cleanup)),
reached through the loopback backend's streaming endpoints.

## Scope, header, refusals

The repository is scope, not a destination: the sidebar's `REPOSITORY IN
VIEW` picker (`Choose a repository`; the clear button's help reads `Clear
the repository scope`) names the tree every count on this screen describes.
Title `Violations`; scope is the repository's directory name; freshness
reads `not scanned`, `no repository selected`, `scanning now`,
`scan failed`, or `<n> files scanned`. Actions: `Scan` / `Stop scan` and,
once findings exist, `Repair` / `Stop repair`.

Validation runs before anything else, each refusal verbatim:

- `Enter a repository path first.`
- `Choose an existing absolute Git repository directory: <path>` — not
  absolute, not a directory, or no `.git`.
- `Tama refuses to mutate a repository not owned by the current user:
  <path>` — UID mismatch.
- `Codex is unavailable. Install and authenticate Codex before confirming
  cleanup.` — repair needs the local headless agent; scan does not.

## Facets and counters

`Rule` ranks rules by how many files they hit — the order an operator
repairs them in — under `Every rule`; `Repository` appears only when the
report covers more than one. Counters: `Violations` (findings across the
scanned repositories), `Files scanned`, `Skipped` (binary or oversized
inputs), `Scan errors` (files the scanner could not read). Per-repository
enumeration failures surface as `The scanner could not enumerate
<owner/repo>` with the error verbatim.

## Centre states

No scope: `No repository is in view` — `Choose a Git repository you own in
the sidebar. Tama enumerates it with the approved pre-write rules and reads
nothing outside it.` Scanning: `Scanning <path>` — `Every tracked file is
checked against the pre-write rules this build declares. Nothing is
written.` Unscanned: `This repository has not been scanned`. Clean:
`No violation in this working tree` — `Every scanned file satisfies the
pre-write rules this build declares.` Over-filtered: `No finding matches
this selection` with `Clear filters`. A scan that failed keeps the previous
report on screen — `Scan failed` with the sentence and `Scan again` — and a
failed repair reports `Repair did not finish clean`.

The findings table is PATH, RULE, HOOK. The inspector shows the selected
finding under the badge `Refused on write`: the hook's own message verbatim,
then Hook and Repository. Unselected, it states the screen's boundary: it
can *Enumerate a repository you own* and *Ask one headless agent to edit the
working tree*; it never can *Commit, push, or move a branch ref*, *Touch a
repository owned by another user*, or *Repair without a final rescan*.

## The repair decision

`Let a headless agent edit <n> files in this working tree`, with four lines
stated verbatim:

1. `One external model agent per repository edits <path> until the findings
   are gone or its bounded rounds are spent. The provider is external to
   Tama.`
2. `Tama requests working-tree edits only. It rejects a changed HEAD, a
   changed checked-out branch and changed local branch refs, and it never
   commits or pushes.`
3. `A final rescan always runs, and the reported result is that rescan
   rather than the agent's own claim.`
4. `Review git status, branch refs, remote state and the final diff
   afterwards.`

Reason code `<n> violations in <m> repositories`; the listing is every file
the findings name; footnote: `the agent runs with Codex; Tama refuses to
start the repair when Codex is absent`. Actions: `Cancel`, destructive
`Repair with a headless agent`, primary `Read the findings first`.

## While a repair runs

The clean bar reports in the command's own place: `A headless agent is
editing the working tree in <path>.`, on stop `Stopping the repair. Partial
edits are preserved and rescanned.`, then `Rescanning the working tree
before reporting the result.` A cancelled clean is a reported failure:
`The clean command was cancelled. Partial working-tree edits remain visible;
inspect them and complete a read-only scan before retrying.` A cleanup that
prints no summary reports `The cleanup finished without printing a
summary.` Scan results with exit status 0 and 1 are both valid reports
(clean, and with violations); anything else is the backend's own refusal
sentence, surfaced verbatim ([runbook](../runbook.md#the-backend-refuses-a-repository)).
