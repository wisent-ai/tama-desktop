# What is Tama

What is Tama, and what is the mental model for reading everything else in
these docs? Tama is the local control surface for coding-agent policy hooks
on one Mac: a sealed catalog of approved hooks, a per-user runtime that
enforces them in live agent sessions, and one desktop application that can
prove which policy is loaded and recover when a hook blocks necessary work.
The whole product is three moving parts — a release that declares, a runtime
that enforces, and an operator surface that verifies and overrides.

## The sealed release declares

Hook policy is authored outside this repository, in a hook source tree the
build selects with `TAMA_HOOK_ROOT` (its generated documentation is titled
the Hooks Rotator catalog). `Scripts/build-app.sh` copies that tree's
`shared-hooks/`, `claude-hooks/`, `codex-hooks/`, and `repo-githooks/`
directories into the app bundle, compiles the sealed Rust backend
(`bin/tama-cli`, `bin/tama-mcp-server`), and seals the result: a SHA-256
digest over every file's path, permission bits, and bytes becomes the
`releaseId` in `release.json`. From then on the release is content-addressed
— a rewritten byte or a changed permission bit changes the identity, and the
installer refuses to install anything whose tree no longer digests to its
recorded id.

Inside the release, `shared-hooks/registry.json` is the declaration: every
hook's id, command, source file, the events it fires on, whether each event
blocks, its timeout, and the human record of what it does, why it exists,
and what side effects it has. The registry model is in
[hook-model](hook-model.md); sealing and installation are in
[hook-releases](hook-releases.md).

## The installed runtime enforces

An explicit operator action installs the bundled release into the user's
home: the release tree lands content-addressed under
`~/Library/Application Support/Tama/hooks-runtime/releases/<release-id>`
with a `current` symlink, and the hook entrypoints land in
`~/.shared-hooks`, `~/.claude/hooks`, `~/.codex/hooks`, `~/.local/bin`, and
the user-global Git hooks path. Installation is transactional — original
files are backed up and restored on failure — and never removes a file
outside those managed roots.

Each supervised agent session then publishes a session record: which release
it loaded, how many hooks are registered and loaded, its recent allow/block
decisions, and the capability it holds. Tama reads those records; it never
writes one. The whole enforcement path fails closed: the runtime pins a
validated Node.js executable into every Node-based hook command and preloads
a version guard before any hook script runs.

## The operator verifies and controls

The Tama desktop app is the human surface ([desktop](desktop.md)). It
compares three identities — the release sealed into the signed app, the
release recorded by `installed.json`, and the release each live session
actually loaded — and calls setup complete only when they match. Its two
mutations point in opposite directions by design
([enforcement-control](enforcement-control.md)):

- **Session-scoped enable.** Tama can enable a hook, or every hook, in
  exactly one live session, through a private request the session's own
  supervisor validates and applies. It can never disable a hook per session.
- **Global emergency disable.** One confirmed, operator-owned action bypasses
  every Tama-managed dispatcher on the machine, records what it moved aside,
  and stays visible until re-enable verifies the bundled release and
  restores everything transactionally.

## What Tama is not

Tama does not author or approve hooks — the catalog is read-only and the app
bundle is authoritative for it at runtime. It does not manage fleets, does
not install policy silently, and does not commit or push repository changes:
the violation scanner is read-only and the agent-assisted cleanup edits only
a selected working tree the operator confirms. Credentials stay in the macOS
Keychain through Wisent Auth; Tama never serializes tokens into its own
state. The boundaries are stated in the [README](../README.md) and the
contracts in [core-contracts](core-contracts.md).

## The first three commands

The desktop release seals its own CLI at
`Tama.app/Contents/Resources/hooks-release/bin/tama-cli`
([cli](cli.md)):

```bash
tama-cli list
```

Every hook in the sealed catalog: id, source path, and the events it fires
on.

```bash
tama-cli validate
```

Structural validation of the catalog and source archive: hook and
orphan-source counts, plus a warning for every hook whose source path cannot
be mapped from its command.

```bash
tama-cli sessions
```

Every live supervised agent session and its hook state — which agent, which
session, and how many hooks are enabled. The end-to-end path is
[quick-start](quick-start.md).
