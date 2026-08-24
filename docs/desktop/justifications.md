# Justifications screen

The register of recorded exceptions, and whether each one still holds.
Justification-gated hooks (`type: requires_justification`) demand a recorded
human reason in a local registry file instead of blocking outright
([hook-model](../hook-model.md#justification-gated-hooks)); this screen
reads those registries and judges every record against its requirement.
Nothing here is red unless a registry cannot be read at all: an incomplete
record is amber — evidence to finish, not an outage to fix.

The current sealed catalog declares no `requires_justification` hooks, so
on a stock install the screen shows its own empty state; the mechanism
ships regardless ([concepts/hook](../concepts/hook.md#kinds-of-hooks)).

## Header and facets

Title `Justifications`; scope is the requirement kind; freshness counts
records. Search prompt: `Search path or justification` (matches target,
justification text, and the recorded quote). Facets: `Registry` (one per
declared registry, danger-toned when unreadable; shown only with more than
one) and `Verdict` — `Every record`, `Holds`, `Incomplete`. The rail footer
`Registry` shows the registry path or `No registry declared`.

## Where records come from

Each `requires_justification` hook declares a registry path under the home
directory (`~` and `~/` resolve; absolute paths pass through). The registry
must be a JSON object keyed by target — otherwise the load fails with
`Justification registry must contain a JSON object: <path>` and the screen
shows `Registry unreadable` with that sentence and the path. Per entry, Tama
reads the requirement's field as the justification (word count is a
whitespace split), `expires_at` as an ISO 8601 timestamp, the declared
direct-user-quote field when the requirement names one, and whether the
target path exists on disk. Tama only reads: it never writes, extends, or
deletes a record, and it never reads the target file's contents.

## Counters and states

`Records`, `Holding` (satisfy the contract), `Incomplete` (missing evidence
or expired), `Minimum words` (required in the requirement's field). Empty
states, verbatim: `This build declares no justification hooks` — `No
catalogued policy has type requires_justification, so there is no registry
to read.`; `This registry holds no records` — `The registry exists and
records no exception yet. Entries appear as hooks write them.` (or, when
unreadable, `Tama could not read the registry, so it can list nothing from
it.`); `No record matches this selection` with `Clear filters`. Loading
reads `Reading the justification registries`.

## The verdict

Checked in order; the first failure names the verdict:

| Verdict | Condition | Holds |
|---|---|---|
| `Target missing` | the target path no longer exists | no |
| `Expired` | `expires_at` is in the past | no |
| `No user quote` | the requirement names a quote field and no non-blank quote is recorded | no |
| `Quote not embedded` | the recorded quote is not contained in the justification text | no |
| `Too short` | word count below the requirement's minimum | no |
| `Holds` | everything above passes | yes |

The table is TARGET, WORDS (`<count>/<minimum>`), EXPIRES (`—` when
unbounded), VERDICT — the chip marks the minority verdict, so a registry
where every record holds gets no chips at all.

## Inspector

Eyebrow is the requirement title, title the target's file name, badge the
verdict. Fields: Target, Target file (`Present on disk` / `Missing on
disk`), Kind, Field, and `Expires` / `Expired` with the timestamp. Below,
the justification exactly as written under the field's own name (`No value
recorded for <field>.` when empty) and, when the requirement demands one,
`DIRECT USER REQUEST`. Unselected, the screen states its boundary: it can
*Read the registries declared by requires_justification hooks* and *Report
which records satisfy their contract*; it never can *Write, extend or delete
a justification* or *Read the target file's contents*.
