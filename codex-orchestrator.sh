#!/usr/bin/env bash
# Codex root orchestrator. Repository writes are blocked by the read-only
# sandbox and the policy hook; Herdr remains the only delegation mechanism.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

if [[ "${HERDR_ENV:-}" != "1" ]]; then
  printf 'codex-orchestrator.sh must run inside a Herdr-managed pane.\n' >&2
  exit 1
fi

instructions="$({ python3 - "$PROFILE_DIR/herdr-instructions.md" <<'PY'
import json
import pathlib
import sys

print(json.dumps(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")))
PY
})"

exec codex \
  --strict-config \
  --profile herdr-orchestrator \
  --config "developer_instructions=$instructions" \
  "$@"
