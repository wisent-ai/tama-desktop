# Security policy

## Reporting

Report vulnerabilities through the private GitHub Security Advisory channel for [`wisent-ai/tama-desktop`](https://github.com/wisent-ai/tama-desktop/security/advisories/new).

Do not place credentials, one-time codes, access or refresh tokens, capability grants, control keys, Apple identities, provisioning profiles, private repository paths or contents, production logs, or exploit details in a public or ordinary issue.

Include:

- affected Tama product version, source revision, and hook release ID;
- affected interface and operating-system version;
- prerequisites and required privilege;
- observed impact;
- a minimal reproduction without real secrets or private source;
- whether the issue is actively exploitable;
- containment already applied;
- whether emergency disable completed successfully.

## Response ownership

Repository maintainers triage the report and coordinate with the owners named in `docs/integrations.md`. Identity revocation, Apple platform approval, device isolation, repository recovery, and organization access remain owned by their authorized operators.

## Supported versions

No stable release is currently published. Security fixes apply to the current development line until a preview or stable release declares a supported-version window in `docs/releases.md` and its release notes.

## Security boundaries

- The unauthenticated inspector reads only the signed bundled catalog/build identity and does not start session monitoring or expose mutation controls.
- Policy-changing UI requires Wisent identity and explicit user intent.
- Identity tokens stay in the macOS Keychain or trusted runtime memory.
- Hook releases are content-addressed and verified before installation.
- Session overrides bind to one accepted agent/session/control-key tuple and use atomic mode-`0600` files.
- Privileged macOS components require operating-system approval; unsupported platforms cannot claim kernel enforcement.
- Repository scans are read-only; cleanup is separately confirmed, bounded, and never commits or pushes. Leaving the authenticated control surface cancels active scan or cleanup process trees without deleting partial working-tree edits.
- External session files, repository contents, CLI output, identity responses, and provider responses are untrusted input.
- Emergency disable and transactional rollback preserve evidence needed for recovery.

Never weaken these boundaries to simplify onboarding, development, testing, or integration setup.
