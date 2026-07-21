#!/usr/bin/env bash
# opencode feature implementer. Herdr metadata is stripped so the session
# behaves like a normal user-driven coding session.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

exec env \
  -u HERDR_ENV \
  -u HERDR_WORKSPACE_ID \
  -u HERDR_TAB_ID \
  -u HERDR_PANE_ID \
  OPENCODE_CONFIG="$PROFILE_DIR/opencode-implementer.json" \
  "${OPENCODE_BIN:-${HOME}/.opencode/bin/opencode}" \
  --agent coder \
  --auto \
  "$@"
