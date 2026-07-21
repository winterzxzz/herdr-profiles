#!/usr/bin/env bash
# opencode peer reviewer. The agent permission config prevents edits,
# commits, pushes, and nested delegation.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

exec env \
  -u HERDR_ENV \
  -u HERDR_WORKSPACE_ID \
  -u HERDR_TAB_ID \
  -u HERDR_PANE_ID \
  OPENCODE_CONFIG="$PROFILE_DIR/opencode-peer.json" \
  "${OPENCODE_BIN:-${HOME}/.opencode/bin/opencode}" \
  --agent reviewer \
  --auto \
  "$@"
