#!/usr/bin/env bash
# Codex peer reviewer. The read-only sandbox and policy hook prevent edits,
# commits, pushes, and nested delegation.
set -euo pipefail

export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

exec env \
  -u HERDR_ENV \
  -u HERDR_WORKSPACE_ID \
  -u HERDR_TAB_ID \
  -u HERDR_PANE_ID \
  codex \
  --strict-config \
  --profile herdr-peer \
  "$@"
