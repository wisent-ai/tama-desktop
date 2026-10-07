#!/usr/bin/env bash
# The formatting gate `.wisent-release.json` declares and `stado quality`
# reads. With --check it lists every Swift source swift-format would change and
# exits 1, writing nothing; without it, `stado quality format` runs it to write
# them. The style is `.swift-format` at the checkout root: swift-format's own
# defaults (`swift-format dump-configuration`) with the four-space indentation
# these sources were written in.
set -euo pipefail
cd "$(dirname "$0")/.."

sources() {
  find Sources Package.swift -type f -name '*.swift' | LC_ALL=C sort
}

case "${1:-}" in
  --check)
    changed=0
    while IFS= read -r file; do
      if ! xcrun swift-format format --configuration .swift-format "$file" | cmp -s - "$file"; then
        printf 'swift-format would change %s\n' "$file"
        changed=1
      fi
    done < <(sources)
    exit "$changed"
    ;;
  '')
    sources | xargs xcrun swift-format format --configuration .swift-format --in-place
    ;;
  *)
    printf 'usage: %s [--check]\n' "$0" >&2
    exit 64
    ;;
esac
