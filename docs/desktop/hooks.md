# Hooks screen

The approved catalog and the per-hook decision that goes with it: what a
policy does, why it exists, which events it gates, and whether the live
session in front of you has it enabled. Three zones — facets, table,
inspector. The catalog itself is read-only here; the sealed registry model
is [hook-model](../hook-model.md).

## Header

Title `Hooks`; scope `session <first-8>` when a live session is selected on
[Session](session.md); freshness counts policies. One action: `Reveal
source`, enabled only when the selected hook has an archived source path.
The toolbar search prompt is `Search hook id, category, event or
description`, and it matches exactly those four fields.

## Facets

- **Enforcement** — `All hooks`, `Blocking` (warning tone while any exist),
  `Non-blocking`.
- **Category** — ranked by count descending, then alphabetically; counts are
  measured inside the current enforcement scope, so the number beside a
  category is the number of rows selecting it produces.
- **In this session** — only with a live session: `Enabled here` /
  `Not enabled here` (warning tone when anything is not enabled).

The rail footer `Selection` reads `<visible> of <total>`.

## Centre

`Catalog re-read failed` (banner over a stale-but-present catalog) and
`Catalog unavailable` (no catalog at all) carry the loader's error sentence
verbatim, with Retry. Loading reads `Reading the approved hook catalog`.
The empty states are exact: `This build carries no hooks` — `The sealed
catalog declares no policies. Rebuild Tama against a tama release that
does.` — and `No hook matches this selection` with a `Clear filters`
action. The table is HOOK, CATEGORY, EVENTS (count), FLAG; the
`Blocking` / `Advisory` chip marks the minority, so when most of the catalog
blocks, the pill moves to the advisory rows.

## Inspector

Eyebrow is the category, title the hook id, badges the status (capitalized;
success only for `active`) plus `Blocking`. Sections: *What it does*, *Why
it exists*, *Side effects* — the registry's own prose — then EVENTS with a
per-event `Blocking` chip and `<timeout>s`, then `Source` (`No archived
source path` for sealed-backend hooks) and `Command`. Unselected: `Choose a
policy to read what it does, why it exists, which events it runs on, and
whether the live session has it enabled.`

## The one mutation

With a live session, the inspector adds `In <agent> session`:
`Enabled` / `Not enabled`, and — only when not enabled — the primary
`Enable in this session`. Enabling restores policy, so it needs no dialog;
the disabling direction does not exist per hook by design
([core-contracts](../core-contracts.md)). The note under the button states
persistence exactly:

- normally: `The override is stored for this agent session and restored
  when the same session is resumed.`
- during a global disable: `All hooks are globally disabled. Enabling writes
  an allowlist entry for this agent session only.`

The mutation reports `Enabling <hook-id> in session <id>…` then
`<hook-id> is enabled in <agent> session <id>.`, over the same validated
request channel as [Session](session.md#mutations)
([concepts/session-enable](../concepts/session-enable.md)).
