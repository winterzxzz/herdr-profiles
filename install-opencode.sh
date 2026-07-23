#!/usr/bin/env bash
# Link the opencode herdr plugins into the user's plugin directory.
#
# These are separate files from herdr-agent-state.js on purpose: that file is
# installed and overwritten by `herdr integration install opencode`, and its own
# header says to add custom plugins beside it rather than edit it.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${OPENCODE_PLUGIN_DIR:-$HOME/.config/opencode/plugins}"

mkdir -p "$PLUGIN_DIR"

link_plugin() {
  local name=$1
  local source="$PROFILE_DIR/opencode-plugins/$name"
  local target="$PLUGIN_DIR/$name"

  if [[ -e "$target" && ! -L "$target" ]]; then
    printf 'Refusing to replace existing file: %s\n' "$target" >&2
    exit 1
  fi

  ln -sfn "$source" "$target"
  printf 'Linked %s -> %s\n' "$target" "$source"
}

link_plugin herdr-no-subagent.js
link_plugin herdr-role-policy.js

printf '\nSubagents are now blocked in every opencode session.\n'
printf 'Override for a single session with OPENCODE_ALLOW_TASK=1.\n'
printf '\nherdr-role-policy is inert unless HERDR_ROLE is set, so ordinary\n'
printf 'sessions are untouched. opencode-supervisor.sh arms it.\n'
