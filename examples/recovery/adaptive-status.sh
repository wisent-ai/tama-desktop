#!/bin/sh
# Recovery triage: inspect adaptive state, drift, and queued repairs.
# Reads only; the first run creates the empty ~/.hooks-adaptive state
# directories and changes nothing else.
set -eu

tama adaptive status

# Nonzero when a live hook is missing or differs from the archive content.
tama adaptive drift || DRIFT=$?

tama adaptive queue

# Repair or apply only after reviewing the reported plan:
# tama adaptive repair <hook-id>
# tama adaptive apply <proposal-dir>

# Exit truthfully with the drift verdict: 0 in sync.
exit "${DRIFT:-0}"
