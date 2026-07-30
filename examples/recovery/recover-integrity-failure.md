# Recover from a catalog or runtime integrity failure

## Goal

Replace corrupt or mismatched Tama bytes with the same immutable verified release and
recover observable product identity without editing managed manifests manually.

## Status

Draft for the first `0.2.x` preview. Controlled fault-injection and recovery evidence are
pending.

## Risk

Destructive/recovery. Replacing an app or runtime while sessions run can leave incompatible
loaded policy, so all supervised sessions must stop first.

## Environment

Supported Mac with a visible **Catalog unavailable**, invalid snapshot, runtime-integrity,
or release-identity error, plus retained zip, digest, provenance, and release notes for the
exact installed tag.

## Preconditions

- Stop all supervised agent sessions and quit Tama.
- Preserve `~/Library/Application Support/Tama`, emergency backups, and the failing app as
  bounded recovery evidence.
- Confirm the retained artifact version is intended; do not use `latest` or another build.

## Inputs

The exact immutable artifact and sidecars for the same product version. Digest verification
must name that artifact and must end in `OK` before replacement.

## Artifacts and side effects

Replaces `Tama.app` with identical published bytes. A later explicit runtime installation
may transactionally replace the installed hook release while preserving prior identity and
restoration evidence.

## Steps

1. Verify the retained zip:
   ```bash
   shasum -a 256 -c Tama-<version>-macOS-arm64.zip.digest
   ```
2. Compare provenance product/source identity and artifact digest with the immutable tag.
3. Move the failing app aside without changing Application Support or managed hook files.
4. Expand the verified zip and install `Tama.app` in the same supported per-user location.
5. Open Tama and inspect Overview before any mutation.
6. If the catalog is valid but installed runtime identity remains rejected, choose
   **Install local runtime**, review scope, and confirm the transactional reinstall.
7. Resume one supervised session only after product, catalog, and installed release
   identities agree.

## Verification

Overview must display the expected product/source identity, a valid catalog, expected hook
release ID, and no integrity error. If runtime reinstall was required, installed and
bundled release IDs must match. The resumed session must not report registry error or
reload requirement.

## Failure path

If digest verification fails, delete the download and fetch all files again from the exact
tag. If the same verified app still reports an invalid catalog, preserve the artifact and
bounded diagnostic for release maintainers; do not create a replacement manifest. If
runtime rollback cannot restore the old symlink, leave sessions stopped and use the
versioned rollback path.

## Cleanup or off-switch

Retain the failing app only until evidence is accepted, then remove it. Keep Application
Support backups according to the release retention decision. Remove no managed source file
unless it is named by the installed manifest and recovery is complete.

## Next

For a version change rather than same-version recovery, use
[`rollback-exact-release.md`](rollback-exact-release.md) or
[`../operations/upgrade-exact-release.md`](../operations/upgrade-exact-release.md).
