"""The qualification evidence a release must carry, checked for validate_artifact.py."""

import os
from pathlib import Path


def check_qualification(qualification, product_version, source_revision, artifact, hook_release, architecture, require, parse_timestamp):
    """Record every way the qualification evidence fails the candidate through `require`."""
    qualification_records = qualification.get("records")
    expected_hook_release_id = (
        hook_release.get("releaseId") if isinstance(hook_release, dict) else None
    )
    require(
        qualification.get("schema") == "ai.wisent.tama.release-qualification.vOne",
        "unexpected qualification evidence schema",
    )
    for field, expected in (
        ("productVersion", product_version),
        ("tag", f"v{product_version}"),
        ("sourceRevision", source_revision),
        ("artifactName", artifact.name),
        ("artifactDigest", os.environ["TAMA_ACTUAL_DIGEST"]),
        ("artifactByteSize", artifact.stat().st_size),
        ("hookReleaseId", expected_hook_release_id),
        ("platform", "macOS"),
        ("architecture", architecture),
    ):
        require(
            qualification.get(field) == expected,
            f"qualification {field} does not match the candidate",
        )
    qualified_at = qualification.get("qualifiedAt")
    require(
        isinstance(qualified_at, str) and bool(qualified_at.strip()),
        "qualification evidence has no completion time",
    )
    qualified_at_timestamp = parse_timestamp(
        qualified_at,
        "qualification completion time",
    )
    require(
        isinstance(qualification_records, list) and bool(qualification_records),
        "qualification evidence contains no execution records",
    )

    required_suite_kinds = {
        "swift-contracts",
        "clean-device-e2e",
        "controlled-recovery-provider-release",
    }
    allowed_suite_kinds = required_suite_kinds | {"canonical-example"}
    covered_suite_kinds = set()
    record_keys = set()
    actual_example_names = []
    if isinstance(qualification_records, list):
        for record in qualification_records:
            if not isinstance(record, dict):
                require(False, "qualification execution record is not an object")
                continue
            kind = record.get("kind")
            name = record.get("name")
            if not isinstance(kind, str) or not kind.strip():
                require(False, "qualification execution record has no kind")
                continue
            if not isinstance(name, str) or not name.strip():
                require(False, "qualification execution record has no name")
                continue
            require(kind in allowed_suite_kinds, f"unsupported qualification record kind: {kind}")
            key = (kind, name)
            require(key not in record_keys, f"duplicate qualification execution record: {kind}/{name}")
            record_keys.add(key)
            require(record.get("status") == "passed", f"qualification did not pass: {kind}/{name}")
            require(record.get("redacted") is True, f"qualification result is not marked redacted: {kind}/{name}")
            for field in (
                "startedAt",
                "endedAt",
                "controlledIdentityLabel",
                "preconditionSnapshot",
                "expectedObservableContract",
                "result",
                "failurePathExercised",
                "cleanupResult",
                "operatorApprovalReference",
            ):
                value = record.get(field)
                require(
                    isinstance(value, str) and bool(value.strip()),
                    f"qualification record {kind}/{name} has no {field}",
                )
            started_at = parse_timestamp(
                record.get("startedAt"),
                f"qualification record {kind}/{name} start time",
            )
            ended_at = parse_timestamp(
                record.get("endedAt"),
                f"qualification record {kind}/{name} end time",
            )
            if started_at is not None and ended_at is not None:
                require(
                    started_at <= ended_at,
                    f"qualification record {kind}/{name} ends before it starts",
                )
            if ended_at is not None and qualified_at_timestamp is not None:
                require(
                    ended_at <= qualified_at_timestamp,
                    f"qualification record {kind}/{name} ends after qualification completion",
                )
            for field, expected in (
                ("tag", f"v{product_version}"),
                ("sourceRevision", source_revision),
                ("artifactDigest", os.environ["TAMA_ACTUAL_DIGEST"]),
                ("hookReleaseId", expected_hook_release_id),
                ("platform", "macOS"),
                ("architecture", architecture),
            ):
                require(
                    record.get(field) == expected,
                    f"qualification record {kind}/{name} has mismatched {field}",
                )
            if kind == "canonical-example":
                actual_example_names.append(name)
            else:
                covered_suite_kinds.add(kind)

    desktop_root = Path(os.environ["TAMA_DESKTOP_ROOT"])
    expected_example_names = sorted(
        path.relative_to(desktop_root).as_posix()
        for path in (desktop_root / "examples").rglob("*.sh")
        if path.is_file()
    )
    require(
        sorted(actual_example_names) == expected_example_names,
        "qualification evidence does not cover every canonical example exactly once",
    )
    require(
        required_suite_kinds.issubset(covered_suite_kinds),
        "qualification evidence does not cover every required suite kind",
    )
