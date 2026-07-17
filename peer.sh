#!/usr/bin/env bash
# Peer reviewer/critic: read-only, spawned ad hoc by the orchestrator to
# review diffs, challenge designs, or give second opinions. Cannot edit.
set -euo pipefail

PROFILE_DIR="$HOME/.herdr-profiles"

exec env \
  -u HERDR_ENV \
  -u HERDR_WORKSPACE_ID \
  -u HERDR_TAB_ID \
  -u HERDR_PANE_ID \
  claude \
  --settings "$PROFILE_DIR/peer.json" \
  --setting-sources project,local \
  "$@"
