#!/usr/bin/env bash
# Install the Codex named profiles without replacing the user's base config.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

mkdir -p "$CODEX_HOME"

link_file() {
  local source=$1
  local target=$2

  if [[ -e "$target" && ! -L "$target" ]]; then
    printf 'Refusing to replace existing file: %s\n' "$target" >&2
    exit 1
  fi

  ln -sfn "$source" "$target"
  printf 'Linked %s -> %s\n' "$target" "$source"
}

link_file "$PROFILE_DIR/codex-orchestrator.config.toml" \
  "$CODEX_HOME/herdr-orchestrator.config.toml"
link_file "$PROFILE_DIR/codex-implementer.config.toml" \
  "$CODEX_HOME/herdr-implementer.config.toml"
link_file "$PROFILE_DIR/codex-peer.config.toml" \
  "$CODEX_HOME/herdr-peer.config.toml"
link_file "$PROFILE_DIR/herdr-profile-policy.py" \
  "$CODEX_HOME/herdr-profile-policy.py"

printf '\nCodex profiles installed in %s.\n' "$CODEX_HOME"
printf 'On first launch, open /hooks and trust the herdr profile policy.\n'
