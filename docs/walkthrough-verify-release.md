# Walkthrough: verify a hook release seal

Can you prove, byte for byte, that a hook release is exactly what was sealed —
and when it is not, name the file that changed? This walkthrough does both,
read-only, against a real sealed release. Every command below was executed
against the release built by `Scripts/build-app.sh` on 2026-08-24; outputs are
pasted verbatim, with the home directory abbreviated to `~` and temp
directories to `$TMP`. The identity model is
[concepts/seal](concepts/seal.md); the scripts are in
[scripts](scripts.md#read-only-integrity-reporters).

## 1. Read the seal

The manifest at the release root records the identity the tree must digest
to:

```console
$ cat .build/Tama.app/Contents/Resources/hooks-release/release.json
{
  "catalogUpdatedAt": "2026-07-03T03:37:52.587318Z",
  "catalogVersion": 1,
  "packageVersion": "0.1.0",
  "releaseId": "35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7",
  "schema": "ai.wisent.tama.hook-release.v1",
  "sealedAt": "2026-08-24T18:19:12.387624+00:00",
  "sourceDirty": false,
  "sourceRevision": "f8b95a61cc431bfd6c494569d4a18b4de15c0381"
}
```

`releaseId` is the SHA-256 tree digest over every file except `release.json`
itself — relative path, permission bits, and bytes, each length-framed
([concepts/seal](concepts/seal.md)).

## 2. Verify the intact release

```console
$ python3 Scripts/verify_hook_release.py
release root: ~/Documents/CodingProjects/Wisent/tama-desktop/.build/Tama.app/Contents/Resources/hooks-release
recorded releaseId: 35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7
actual tree digest: 35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7
sealed at: 2026-08-24T18:19:12.387624+00:00
source dirty: False
result: intact
```

`report_hook_release_integrity.py` answers the same question with the
installer's own digest implementation imported directly, so the two can
never describe different rules:

```console
$ python3 Scripts/report_hook_release_integrity.py
root:   ~/Documents/CodingProjects/Wisent/tama-desktop/.build/Tama.app/Contents/Resources/hooks-release
sealed: 35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7
actual: 35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7
verdict: intact
```

## 3. Drift one byte and catch it

Work on a mtime-preserving copy — never edit a real release directory
([hook-releases](hook-releases.md#verifying-a-release-by-hand)):

```console
$ cp -pR .build/Tama.app/Contents/Resources/hooks-release "$TMP/hooks-release"
$ printf '\n' >> "$TMP/hooks-release/shared-hooks/block_inline_execution.sh"
$ python3 Scripts/verify_hook_release.py "$TMP/hooks-release"
release root: $TMP/hooks-release
recorded releaseId: 35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7
actual tree digest: f6048ed4d7d9d6d4af43334005be351ec467e16a0743d6741fc4f65aa7ea1398
sealed at: 2026-08-24T18:19:12.387624+00:00
source dirty: False
result: DRIFTED
written after the seal:
  2026-08-24T22:05:30.282534+00:00 shared-hooks/block_inline_execution.sh
```

One appended newline changed the whole identity, and the report names the
one file written after `sealedAt`. The installer meeting this tree would
refuse with `Bundled Tama hook release failed its integrity check`
([runbook](runbook.md#bundled-tama-hook-release-failed-its-integrity-check));
this walkthrough is how you find out *which file* earned that refusal.

```console
$ python3 Scripts/report_hook_release_integrity.py "$TMP/hooks-release"
root:   $TMP/hooks-release
sealed: 35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7
actual: f6048ed4d7d9d6d4af43334005be351ec467e16a0743d6741fc4f65aa7ea1398
verdict: MISMATCH
covered by the digest but never installed: 0
written after sealedAt 2026-08-24T18:19:12.387624+00:00: 1
  shared-hooks/block_inline_execution.sh
```

`covered by the digest but never installed` is the build-residue detector: a
`.pyc` file some hook wrote after sealing drifts the digest exactly like
tampering, and this line is what tells those cases apart.

## 4. Drift a permission bit and catch that too

The digest covers each file's mode, so a `chmod` with identical bytes is
still drift — the case least likely to be guessed from a byte-comparison
mental model:

```console
$ cp -pR .build/Tama.app/Contents/Resources/hooks-release "$TMP2/hooks-release"
$ chmod 755 "$TMP2/hooks-release/shared-hooks/registry.json"
$ python3 Scripts/verify_hook_release.py "$TMP2/hooks-release"
release root: $TMP2/hooks-release
recorded releaseId: 35204a12836395942bc7229c4136e5f0aeade6f6b8a73908e09229504f6dd3c7
actual tree digest: d052632e333e4bac5799da220b311e017457ade575bc24083425c7fbdab226c3
sealed at: 2026-08-24T18:19:12.387624+00:00
source dirty: False
result: DRIFTED
no file is newer than the seal -- the drift is a permission change,
a deletion, or a file whose timestamp was preserved on copy.
```

No file is newer than the seal, and the script says exactly what that
means: the drift is a mode change, a deletion, or a timestamp-preserving
copy — mtime cannot attribute it, but the digest still refuses it.

## 5. What to do with a real mismatch

Nothing in a release directory is repairable in place: the recovery for a
genuinely drifted release is reinstalling the same verified app artifact
([operations](operations.md#failure-and-recovery)). To check what is already
installed under `~/Library/Application Support/Tama`, continue with
[walkthrough-runtime-status](walkthrough-runtime-status.md).
