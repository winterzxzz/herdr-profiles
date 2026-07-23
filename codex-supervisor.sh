#!/usr/bin/env bash
# Codex room supervisor. Read-only sandbox plus a policy hook that allows only
# read-only `herdr` subcommands, so it can observe the room and notify the human
# but never change either.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

if [[ "${HERDR_ENV:-}" != "1" ]]; then
  printf 'codex-supervisor.sh must run inside a Herdr-managed pane.\n' >&2
  exit 1
fi

instructions="$({ python3 - "$PROFILE_DIR/supervisor-instructions.md" <<'PY'
import json
import pathlib
import sys

print(json.dumps(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")))
PY
})"

exec codex \
  --strict-config \
  --profile herdr-supervisor \
  --config "developer_instructions=$instructions" \
  "$@"
