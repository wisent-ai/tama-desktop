# Configuration

Tama has no required environment variables and no free-form settings file
for a supported installation: setup choices are explicit actions in the app,
and everything durable lives in known files with known schemas. This page
maps that surface — where state lives, which environment variables the
bundled scripts and runtime honor, and the few user-defaults keys the app
itself keeps. Build- and release-time variables (signing identities,
provisioning profiles, channels) are maintainer-only and tabled in
[operations](operations.md).

## State Tama owns

Everything under `~/Library/Application Support/Tama`:

| Path | Content |
|---|---|
| `hooks-runtime/releases/<release-id>/` | Content-addressed installed hook releases |
| `hooks-runtime/current` | Symlink to the active release, replaced atomically |
| `hooks-runtime/installed.json` | Installed identity: release id, checksum, versions, managed files, pinned Node (`ai.wisent.tama.installed-hook-release.v1`) |
| `hook-emergency-state.json` | Durable disabled flag (`ai.wisent.tama.hook-emergency-state.v1`) |
| `emergency-backup/manifest.json` | What emergency disable moved and emptied, recorded once |
| `emergency-backup/claude-settings.json`, `codex-hooks.json` | Original provider configs, restored on re-enable |
| `session-control/*.session.json` | Supervisor-owned live session records (`ai.wisent.tama.session-control.v2`) |
| `session-control/*.override.json`, `*.request.json`, `*.response.json` | Session overrides and the private request/response exchange |

Never repair `installed.json`, `current`, or the emergency manifest by hand
as a normal procedure ([operations](operations.md)).

## Managed per-user files

Installation writes hook entrypoints only to documented per-user locations
([hook-releases](hook-releases.md)): `~/.shared-hooks` (including the
rewritten `registry.json` and generated `HOOKS.md`), `~/.claude/hooks` and
`~/.claude/settings.json`, `~/.codex/hooks` and `~/.codex/hooks.json`,
`~/.local/bin/tama-agent`, the `pre-commit`/`pre-push` dispatchers at the
user-global Git hooks path (`git config --global core.hooksPath`, default
`~/.config/git/hooks`, originals preserved as `<name>.before-tama`), and
approved `.githooks` files in matching project checkouts. The OMP adapter
`~/.shared-hooks/omp-shared-hooks.js` is registered through
`omp config set extensions`.

## Script and runtime environment variables

Honored by the bundled installer (`install_hook_release.py`), the emergency
switch (`emergency_disable_hooks`), and the generated launchers:

| Variable | Read by | Purpose |
|---|---|---|
| `TAMA_HOME` | emergency switch | Target home directory; defaults to `$HOME` |
| `TAMA_EMERGENCY_ACTION` | emergency switch | `disable` (default) or `enable` |
| `TAMA_SKIP_SESSION_RESTART` | emergency switch | `1` skips the supervised-session pause/resume |
| `TAMA_HOOK_RELEASE_ROOT` | emergency switch | Release root override; defaults to the bundled `hooks-release` |
| `TAMA_HOOK_INSTALLER` | emergency switch | Installer path override |
| `TAMA_SESSION_SUPERVISOR` | emergency switch | Supervisor script override |
| `TAMA_OMP` | installer | The `omp` executable used to register the OMP adapter |
| `TAMA_PYTHON` | `tama-agent` launcher | Python 3 used for the universal session runtime |
| `TAMA_NODE_EXECUTABLE`, `TAMA_NODE_PREFLIGHT` | exported by the launcher | The pinned Node executable and version guard, for semantic dispatch |
| `AGENT_HOOK_REGISTRY` | OMP adapter | Registry path override; defaults to `~/.shared-hooks/registry.json` |
| `TAMA_CLEAN_DISABLED` | `tama-cli clean` | `1` disables the cleanup command entirely |
| `TAMA_HOOK_SOURCE_ROOT` | `Scripts/stage_live_hook_release.py` | Hook source tree for staging a developer release |

Debug-only seams (`TAMA_HOOK_ROOT` for the catalog root, `TAMA_TEST_IDENTITY`
for UI tests) are compiled out of distributed builds
([operations](operations.md)).

## Application defaults

The app stores minimal preferences in user defaults for bundle id
`ai.wisent.tama.desktop`:

- `tama.hasCompletedSetup` — recorded only by the successful setup handoff;
  delete it to repeat guided setup without changing enforcement state
  ([onboarding](onboarding.md));
- the first-use journey's progress, stored under the `tama.onboarding.v1`
  namespace; the journey's transport reads its token from the
  `TAMA_STADO_INTEGRATION_TOKEN` environment key, and a bundled journey
  definition is the fallback.

Authentication state is not configuration: the Wisent session lives in the
macOS Keychain through Wisent Auth, and Tama does not duplicate it in
preferences ([integrations](integrations.md)).
