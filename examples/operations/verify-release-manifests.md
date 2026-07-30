# Verify an immutable Tama artifact and its manifests

## Goal

Prove one downloaded Tama zip matches its digest, release provenance, embedded build
identity, exact dependency revisions, and independently sealed hook release.

## Status

Draft for the first `0.2.x` preview. Safe local execution awaits a published preview.

## Risk

Read-only. This expands a zip into one new isolated directory and does not launch Tama.

## Environment

Apple-silicon macOS 14 or newer with `shasum`, `ditto`, and Python 3, plus the zip,
`.digest`, `.provenance.json`, and release notes from one exact immutable tag.

## Preconditions

- Use an empty directory containing only those downloaded release files.
- Obtain the expected semantic version from the exact GitHub Release.
- Do not use a moving `latest` URL or a previously expanded app.

## Inputs

Set `ARTIFACT` to the exact zip filename and `EXPECTED_VERSION` to the tag without `v`.
Reject empty values or a filename other than
`Tama-$EXPECTED_VERSION-macOS-arm64.zip`.

## Artifacts and side effects

Creates only `./expanded/Tama.app`. Reads public sidecars, embedded `tama-build.json`, and
`hooks-release/release.json`. It installs nothing.

## Steps

1. Run in the isolated directory:
   ```bash
   : "${ARTIFACT:?set exact artifact filename}"
   : "${EXPECTED_VERSION:?set exact semantic version}"
   test "$ARTIFACT" = "Tama-$EXPECTED_VERSION-macOS-arm64.zip"
   test -f "$ARTIFACT.digest"
   test -f "$ARTIFACT.provenance.json"
   shasum -a 256 -c "$ARTIFACT.digest"
   test ! -e expanded
   mkdir expanded
   ditto -x -k "$ARTIFACT" expanded
   ```
2. Inspect `expanded/Tama.app/Contents/Resources/tama-build.json` and the nested
   `hooks-release/release.json`.
3. Compare product/source identity, channel, platform, architecture, artifact digest and
   size, hook/catalog identity, canonical-examples path/URL/source revision, dirty flags,
   and every resolved dependency revision.
4. Confirm the app and Network Extension short versions equal `EXPECTED_VERSION`.

## Verification

`shasum` must report the exact artifact as `OK`. All component versions must equal
`EXPECTED_VERSION`; dirty flags must be false; source, hook, example, and dependency
revisions must be nonempty; the canonical-examples URL must use the same exact tag; and
sidecar plus embedded identities must agree.

## Failure path

Any missing field, mismatch, dirty source, wrong architecture, or unresolved dependency
invalidates the artifact. Delete the isolated download and expansion, fetch all files again
from the exact tag, and never repair provenance JSON manually.

## Cleanup or off-switch

Remove only `expanded`, which this example created. Retain immutable release files according
to the release policy.

## Next

Install through
[`../getting-started/first-kernel-gated-session.md`](../getting-started/first-kernel-gated-session.md)
or use [`upgrade-exact-release.md`](upgrade-exact-release.md).
