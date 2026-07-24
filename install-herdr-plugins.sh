#!/usr/bin/env bash
# Link this repo's Herdr plugins into the running Herdr instance.
#
# Separate from install-codex.sh and install-opencode.sh because these are
# Herdr's own plugins, not agent-CLI config: they are registered through the
# herdr CLI rather than by dropping files into a config directory, and they
# need a running Herdr server to link against.
#
# Skipping this step leaves the room without an attention broker, which is
# silent in the worst way: the Lead simply never gets woken, and looks merely
# idle rather than broken.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HERDR_BIN="${HERDR_BIN:-herdr}"

if ! command -v "$HERDR_BIN" >/dev/null 2>&1; then
  printf 'herdr CLI not found. Set HERDR_BIN or add it to PATH.\n' >&2
  exit 1
fi

link_plugin() {
  local name=$1
  local source="$PROFILE_DIR/plugins/$name"

  if [[ ! -f "$source/herdr-plugin.toml" ]]; then
    printf 'Not a Herdr plugin (no herdr-plugin.toml): %s\n' "$source" >&2
    exit 1
  fi

  # `plugin link` is idempotent: relinking an already-linked root just
  # refreshes the manifest, so this is safe to re-run after a pull.
  "$HERDR_BIN" plugin link "$source" >/dev/null
  printf 'Linked %s\n' "$name"
}

link_plugin attention-broker

printf '\n'
"$HERDR_BIN" plugin list

cat <<'EOF'

The attention broker finds the Lead by seat name, so the room is not wired up
until the Lead's pane is named:

    herdr pane rename <lead-pane-id> "Lead"

Until then every event is held in the unresolved queue and the plugin logs a
warning. Inspect with:

    herdr plugin action invoke local.herdr-attention-broker.status
EOF
