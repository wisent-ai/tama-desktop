# Examples

Runnable, commented shell scripts, one bounded CLI outcome each. Every
script states whether it reads or mutates before its first command; mutation
scripts require explicit environment inputs before they act. The command
surface is documented in [docs/cli.md](../docs/cli.md); the two integrity
scripts are executed end-to-end with pasted output in the walkthroughs.

Read-only scripts assume the sealed `tama` CLI on PATH
(`getting-started/install-cli.sh` links it from an installed
`Tama.app`); the integrity scripts run from a checkout and default to the
release inside `.build/Tama.app`.

| Script | Reads or mutates | Outcome |
|---|---|---|
| `getting-started/install-cli.sh` | mutates (one symlink) | Link the bundled `tama-cli` onto PATH as `tama`; refuses to replace unrelated entries |
| `getting-started/status.sh` | reads | Catalog validation counts and every live supervised session |
| `integrity/verify-release-seal.sh` | reads | A release tree digested against its recorded `releaseId`, with drift attribution ([walkthrough](../docs/walkthrough-verify-release.md)) |
| `integrity/runtime-status.sh` | reads | Live sessions plus every installed release verified against its content-addressed name ([walkthrough](../docs/walkthrough-runtime-status.md)) |
| `core/hooks-list.sh` | reads | The hook catalog, then one exact hook |
| `core/provider-coverage.sh` | reads | Registry-declared provider coverage from the loopback backend |
| `core/scan-repository.sh` | reads | First rule violation per file in one owned repository |
| `core/clean-repository.sh` | mutates (working tree, external provider) | Headless-agent repair with a final independent rescan |
| `operations/mcp-config.sh` | reads | The exact MCP server fragment for this release |
| `operations/install-user-git-hooks.sh` | mutates (Git hooks path and config) | Reviewed install plan, then the user-global Git dispatchers |
| `recovery/adaptive-status.sh` | reads (creates empty state dirs on first run) | Adaptive layer status, drift, and queued repairs |
