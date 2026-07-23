#!/usr/bin/env bash
# Link the opencode subagent block into the user's plugin directory.
#
# This is a separate file from herdr-agent-state.js on purpose: that file is
# installed and overwritten by `herdr integration install opencode`, and its own
# header says to add custom plugins beside it rather than edit it.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${OPENCODE_PLUGIN_DIR:-$HOME/.config/opencode/plugins}"

mkdir -p "$PLUGIN_DIR"

source="$PROFILE_DIR/opencode-plugins/herdr-no-subagent.js"
target="$PLUGIN_DIR/herdr-no-subagent.js"

if [[ -e "$target" && ! -L "$target" ]]; then
  printf 'Refusing to replace existing file: %s\n' "$target" >&2
  exit 1
fi

ln -sfn "$source" "$target"
printf 'Linked %s -> %s\n' "$target" "$source"
printf '\nSubagents are now blocked in every opencode session.\n'
printf 'Override for a single session with OPENCODE_ALLOW_TASK=1.\n'
