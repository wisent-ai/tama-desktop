#!/usr/bin/env bash
# The formatting gate `.wisent-release.json` declares and `stado quality`
# reads. With --check it lists every Swift source swift-format would change and
# fails, writing nothing; without it, `stado quality format` runs it to write
# them. The style is `.swift-format` at the checkout root: swift-format's own
# defaults (`swift-format dump-configuration`) with the four-space indentation
# these sources were written in. Each source path is read as one whole line, so
# a directory whose name holds a space is one path, not two.
set -euo pipefail
cd "$(dirname "$0")/.."

sources() {
  find Sources Package.swift -type f -name '*.swift' | LC_ALL=C sort
}

case "$*" in
  --check)
    unchanged=true
    while IFS= read -r file; do
      if ! xcrun swift-format format --configuration .swift-format "$file" | cmp -s - "$file"; then
        printf 'swift-format would change %s\n' "$file"
        unchanged=false
      fi
    done < <(sources)
    "$unchanged"
    ;;
  '')
    while IFS= read -r file; do
      xcrun swift-format format --configuration .swift-format --in-place "$file"
    done < <(sources)
    ;;
  *)
    printf 'usage: %s [--check]\n' "$0" >&2
    false
    ;;
esac
