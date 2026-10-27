#!/bin/sh
# Local mutation: expose the CLI embedded in one installed Tama.app on the current user's PATH.
# A matching link is retained; any other existing entry is left untouched.
# Usage: TAMA_APP=<path to the installed Tama.app> sh install-cli.sh
set -eu

TAMA_APP=${TAMA_APP:?set TAMA_APP to the installed Tama.app whose CLI is linked}
TAMA_CLI="$TAMA_APP/Contents/Resources/hooks-release/bin/tama"
TAMA_LINK="$HOME/.local/bin/tama"

[ -f "$TAMA_CLI" ] || { echo "Tama CLI not found: $TAMA_CLI"; false; }

if [ -L "$TAMA_LINK" ]; then
  [ "$(readlink "$TAMA_LINK")" = "$TAMA_CLI" ] || {
    echo "Refusing to replace existing link: $TAMA_LINK"
    false
  }
elif [ -e "$TAMA_LINK" ]; then
  echo "Refusing to replace existing entry: $TAMA_LINK"
  false
else
  mkdir -p "$HOME/.local/bin"
  ln -s "$TAMA_CLI" "$TAMA_LINK"
fi

echo "Tama CLI entrypoint: $TAMA_LINK"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo 'Add $HOME/.local/bin to PATH before invoking tama.' ;;
esac
