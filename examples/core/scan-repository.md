# Scan one repository without changing it

## Goal

Run the bundled production policy scanner against one owned Git repository and obtain an
explicit clean or violation report without changing the working tree.

## Status

Draft for the first `0.2.x` preview. Safe local execution evidence is pending.

## Risk

Read-only. The scanner reads paths and policy-relevant text but does not commit, push, or
invoke a cleanup agent.

## Environment

Supported Tama app, Node.js 20 or newer, Python 3 where required by bundled hooks, and one
existing local Git repository owned by the current macOS user. Network access is not
required for scan.

## Preconditions

- Record the repository's current working-tree state outside Tama.
- Use a repository whose contents may be inspected under the applicable policy.
- Confirm the bundled catalog is valid. Runtime installation and privileged backend are
  not prerequisites for this optional workflow.

## Inputs

Enter one absolute repository directory. Relative paths, nonexistent paths, non-Git
directories, symlink escapes, and directories not owned by the current user are rejected.

## Artifacts and side effects

Reads repository files and bundled policy. Displays counts, rule groups, skipped paths,
and bounded errors in memory. It must not write the repository or invoke Codex.

## Steps

1. Open **Violations**.
2. Enter the absolute path to the selected repository.
3. Choose **Scan** and wait for the bounded command to finish.
4. Inspect **Summary**, **Problems**, each repository, grouped rule violations, skipped
   files, and scan errors.
5. Do not choose **Clean violations**.

## Verification

Success is one parsed report whose totals equal the visible per-repository entries. It may
show zero violations or explicit violations/problems; both are valid semantic reports.
Rejected usage or execution failure is not a successful scan. Independently confirm the
repository working-tree state is unchanged before treating the example as executed.

## Failure path

If the path is rejected, choose an existing absolute owned Git repository. If Node.js is
missing or older than 20, install a supported release or set the documented developer-only
`TAMA_NODE`, then retry explicitly. If the bundled CLI is missing or output unreadable,
reinstall the exact verified Tama artifact; unrelated catalog and session workflows remain
available.

## Cleanup or off-switch

No cleanup is required. Clear the path or quit Tama. Do not delete scanner state by hand.

## Next

If the report contains violations and the working tree is safely recoverable, follow
[`clean-repository-violations.md`](clean-repository-violations.md).
