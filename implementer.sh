#!/usr/bin/env bash
# Feature implementer: the only profile with edit rights. Herdr env is
# stripped and user-level settings are skipped so it has no knowledge of the
# orchestration layer; it should behave as if a human user is driving it.
set -euo pipefail

PROFILE_DIR="$HOME/.herdr-profiles"

exec env \
  -u HERDR_ENV \
  -u HERDR_WORKSPACE_ID \
  -u HERDR_TAB_ID \
  -u HERDR_PANE_ID \
  claude \
  --settings "$PROFILE_DIR/implementer.json" \
  --setting-sources project,local \
  "$@"
