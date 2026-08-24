# Coverage screen

Which runtime carries which hook, as the registry declares it. The screen
answers "is Codex actually covered on this machine" without a terminal —
and is explicit that these are declared mappings, not live execution
evidence, because the data says so in every row: the rail footer reads
`Evidence` / `Registry-declared mappings, not live execution`, and each
provider's own evidence sentence — captured live from the sealed release —
is `Registry-declared mappings; not live execution evidence.`

## Where the data comes from

A plain GET of `/v1/coverage` on the loopback backend
([cli](../cli.md#the-desktop-backend)), read on first visit and re-read
only on demand — coverage is registry content, so polling it would imply it
changes. Against the release sealed on 2026-08-24, the `claude` provider
reports adapter `~/.claude/settings.json`, 95 declared mappings, 57 hooks,
9 events. A failed read shows `Coverage could not be read` with the error
sentence and Retry.

## Header, facets, counters

Title `Coverage`; scope is the selected provider; freshness reads
`reading now`, `read <time>`, or `not read yet`; the one action is `Re-read
coverage`. The `Provider` facet lists `Every provider` (total mappings) and
each provider with its mapping count — warning-toned when it maps nothing.
Counters: `Providers` (declared in this release), `Mappings` (event to
runtime pairs), `Hooks covered` (distinct policies reachable), `Without
mappings` (providers nothing runs through; warns when nonzero).

## States and table

Empty registry: `The registry declares no coverage` — `No runtime in this
release claims any catalogued event.` A provider with no mappings:
`<provider> maps no hook`, with the registry's own note when it declares
one, else `The registry lists the provider and declares no event mapping
for it, so nothing runs through it.`, and a `Show every provider` action.
Loading reads `Reading declared provider coverage`. The table is HOOK,
EVENT, RUNTIME EVENT, PROVIDER.

## Inspector

Selecting a provider (or any of its rows) shows: badges for the coverage
kind (`declared`) and `No mappings` when uncovered; fields `Declared
mappings`, `Hooks`, `Events`, `Adapter path` (`No adapter declared`), and
`Live coverage required` — `yes` / `no` / `not declared`, the release's own
statement of whether it demands live coverage evidence for this provider.
Below, the evidence sentence and any registry note, verbatim. Unselected:
`Choose a provider to read its adapter path, whether the release demands
live coverage evidence for it, and what the registry says its coverage is
based on.` The boundary is stated on the screen: it can *List declared
event to runtime mappings* and *Name the adapter file each provider reads*;
it never can *Prove a hook ran in that runtime* or *Edit an adapter
configuration*.

Coverage is what *should* dispatch; what is loaded and deciding right now is
[Posture](posture.md) ([concepts/posture](../concepts/posture.md#not-to-be-confused-with)).
