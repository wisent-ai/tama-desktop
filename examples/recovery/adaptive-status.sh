#!/bin/sh
# Read-only recovery triage: inspect adaptive state, drift, and queued repairs.
set -eu

tama adaptive status
tama adaptive drift
tama adaptive queue

# Apply or repair only after reviewing the reported plan:
# tama adaptive repair <hook-id>
# tama adaptive apply <hook-id>
