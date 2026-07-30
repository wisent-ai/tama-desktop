# Package and publish one immutable Tama release

## Goal

Produce one signed, timestamped, integrity-attributed Tama artifact from an exact signed
tag and publish those exact bytes once with complete release notes and sidecars.

## Status

Draft for release maintainers. Controlled Apple/GitHub infrastructure and full release
qualification evidence are required before execution.

## Risk

Credentialed, provider-facing, and destructive publication. Apple notarization and GitHub
Release creation are externally visible; published immutable bytes must not be replaced.

## Environment

Clean maintainer Mac with Xcode, Apple release certificates/profiles, a notarytool Keychain
profile, authenticated `gh`, clean `tama-desktop` and hook-source repositories, and an exact
signed Git tag pointing at `HEAD`.

## Preconditions

- Every earlier product stage and release-qualification suite is complete.
- `CHANGELOG.md` contains a dated section for the tag version and no `Unreleased` marker in
  that section.
- `Package.resolved` is committed and resolves every dependency to an exact revision.
- App and Network Extension profiles, signing identity, and notary profile are dedicated
  release credentials unavailable at runtime.
- The target GitHub Release and local release output do not exist.

## Inputs

Export `WISENT_CODESIGN_IDENTITY`, `WISENT_APP_PROVISIONING_PROFILE`,
`WISENT_NETWORK_FILTER_PROVISIONING_PROFILE`, and `WISENT_NOTARY_PROFILE`.
Optionally select a clean hook source with `TAMA_HOOK_ROOT`. All values must refer to the
release operator's controlled resources; never commit them.

## Artifacts and side effects

Packaging writes an immutable zip, `.digest`, and `.provenance.json` under
`.build/releases/<version>`, submits every candidate to Apple notarization, staples the
app, and signs/timestamps components. Publication creates one GitHub Release and uploads
those exact files plus notes. It never receives runtime Wisent credentials.

## Steps

1. Confirm the signed tag equals `HEAD` and both source trees are clean.
2. Run the already-approved release qualification suite and attach its bounded evidence.
3. In the repository root run:
   ```bash
   Scripts/package-release.sh
   ```
4. Independently verify codesign, the stapled notarization ticket when required, artifact
   digest, provenance, embedded build identity, dependency revisions, and hook identity.
5. Review the dated changelog section and prepare release notes in the required headings.
6. Publish once:
   ```bash
   Scripts/publish-release.sh
   ```
7. Read the GitHub Release by its exact tag and compare uploaded byte sizes/digests with
   local immutable output.
8. Install the published zip on a clean supported Mac and complete the onboarding example
   under separate controlled device authorization.

## Verification

Success requires one GitHub Release at the exact signed tag, all three immutable files,
matching local/remote digests, complete release-note headings, valid signing/notarization,
clean source provenance, exact dependency revisions, and successful clean-device
onboarding. Packaging or upload exit alone is insufficient.

## Failure path

Any dirty source, unsigned/wrong tag, missing changelog section, absent identity/profile,
version conflict, unresolved dependency, failed signing/notarization, existing output, or
existing GitHub Release stops publication. Preserve evidence, revoke compromised
credentials, and correct the source contract; never overwrite or rebuild bytes under the
same version.

## Cleanup or off-switch

Retain immutable local and published artifacts according to the channel policy. Remove only
notarization scratch output owned by packaging. Revoke temporary GitHub/Apple credentials
and keep the previous supported artifact available for rollback.

## Next

Qualify installation with
[`../getting-started/first-kernel-gated-session.md`](../getting-started/first-kernel-gated-session.md)
and preserve rollback evidence with
[`../recovery/rollback-exact-release.md`](../recovery/rollback-exact-release.md).
