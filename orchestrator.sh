#!/usr/bin/env bash
# Root orchestrator: full Herdr instructions in the system prompt (survives
# compaction), no edit rights. Run inside a Herdr-managed pane.
set -euo pipefail

PROFILE_DIR="$HOME/.herdr-profiles"

exec claude \
  --settings "$PROFILE_DIR/orchestrator.json" \
  --append-system-prompt "$(cat "$PROFILE_DIR/herdr-instructions.md")" \
  "$@"
