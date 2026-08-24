# Install plan screen

Where an install would write, scope by scope, and the MCP snippet that goes
with it — so an operator approving a privileged install can see which files
it would touch first. The plan is read-only: the screen states target paths
and performs none of the changes. The command behind it is the sealed CLI's
`install-plan` ([cli](../cli.md#read-only-commands)), served as a plain GET
of `/v1/install-plan` on the loopback backend.

## Header and signals

Title `Install plan`; scope `planned changes` once a plan is loaded;
freshness reads `reading now`, `read <time>`, or `not read yet`; the one
action is `Re-read plan`. The signal strip states `Archive root` (the
release the plan derives from), `Scopes`, and `Active by archive alone` —
`Some` / `None`, where `None` is the healthy state: nothing in this product
activates just because the archive exists.

## Levels

One section per scope level, ordered agent/app → editor → MCP →
user-global Git → repo/project Git → OS-level. Each shows the level name,
its first note as the detail, and a trailing `active` or `needs a runtime`.
Fields are the plan's own keys with camel case humanized into labels
(`codexSettings` reads as CODEX SETTINGS); a target the plan reports as
null renders `Not configured` — omitting the row would hide the fact.
Against the release sealed on 2026-08-24 the plan reports, among others:
`user-global Git hooks: ~/.config/git/hooks`, `repo/project Git hooks: git
config core.hooksPath .githooks`, and `OS-level policy: outside Tama`.

## MCP server

`Paste this into a client configuration to expose the bundled Tama tools.`
The snippet is the backend's `/v1/mcp-config` answer — the same JSON
`tama-cli mcp-config` prints, naming the bundled `tama-mcp-server` — read
lazily alongside the plan. Loading reads `Reading the MCP snippet`; a
failure shows `MCP snippet could not be read` with the sentence.

## States

Before any read: `No plan has been read yet` — `The plan is derived from
the bundled release and your home directory. Nothing is written to read
it.` — with a `Read the plan` action. A failed read shows `Install plan
could not be read` with the error verbatim and Retry; a plan document
without an `archiveRoot` string and `levels` object is refused as
malformed rather than partially rendered.

The mutation this plan previews — the transactional install itself — is
documented in [hook-releases](../hook-releases.md#installation); the
user-global Git dispatcher install has a runnable example at
[`../../examples/operations/install-user-git-hooks.sh`](../../examples/operations/install-user-git-hooks.sh).
