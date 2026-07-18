#!/usr/bin/env bash
# Codex feature implementer. Herdr metadata is removed so the session behaves
# like a normal user-driven coding session.
set -euo pipefail

export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

exec env \
  -u HERDR_ENV \
  -u HERDR_WORKSPACE_ID \
  -u HERDR_TAB_ID \
  -u HERDR_PANE_ID \
  codex \
  --strict-config \
  --profile herdr-implementer \
  "$@"
