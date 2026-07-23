#!/usr/bin/env bash
# opencode room supervisor — the default Supervisor, because its model is the
# cheapest available and this seat exists to spend model budget instead of Lead
# context.
#
# Enforcement is split on purpose. The inline config below denies whole tool
# classes, but opencode's bash permissions are greedy glob patterns: an allow
# for "herdr agent read *" also matches "herdr agent read x && herdr pane close
# y". The real allowlist therefore lives in the herdr-role-policy plugin, which
# this wrapper arms by exporting HERDR_ROLE. Install it with ./install-opencode.sh.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${HERDR_ENV:-}" != "1" ]]; then
  printf 'opencode-supervisor.sh must run inside a Herdr-managed pane.\n' >&2
  exit 1
fi

plugin="${OPENCODE_PLUGIN_DIR:-$HOME/.config/opencode/plugins}/herdr-role-policy.js"
if [[ ! -e "$plugin" ]]; then
  printf 'herdr-role-policy plugin is not installed at %s\n' "$plugin" >&2
  printf 'Run ./install-opencode.sh first; without it the supervisor can mutate the room.\n' >&2
  exit 1
fi

config="$(python3 - "$PROFILE_DIR/supervisor-instructions.md" <<'PY'
import json
import pathlib
import sys

instructions = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")

config = {
    "$schema": "https://opencode.ai/config.json",
    # BridgeMemory can carry room context between sessions; an auditor should
    # judge the room it can currently see, not one it remembers.
    "mcp": {"bridgememory": {"enabled": False}},
    "agent": {
        "herdr-supervisor": {
            "mode": "primary",
            "model": "opencode/deepseek-v4-flash-free",
            "variant": "medium",
            "description": "Herdr room supervisor — read-only auditor, reports anti-patterns",
            # prompt lands in the system-prompt layer, so it survives compaction.
            "prompt": instructions,
            "permission": {
                # Deny everything, then allow reads. Last match wins, so the
                # catch-all must come first.
                "*": "deny",
                "read": "allow",
                "glob": "allow",
                "grep": "allow",
                "list": "allow",
                # Coarse gate only. The plugin is what actually distinguishes
                # `herdr agent read` from `herdr pane close`.
                "bash": {
                    "*": "deny",
                    "herdr *": "allow",
                    "git status *": "allow",
                    "git log *": "allow",
                    "git diff *": "allow",
                    "git show *": "allow",
                    "git worktree list": "allow",
                    "cat *": "allow",
                    "ls": "allow",
                    "ls *": "allow",
                    "grep *": "allow",
                    "rg *": "allow",
                },
                "edit": "deny",
                "task": "deny",
                "skill": "deny",
                "todowrite": "deny",
                "webfetch": "deny",
                "websearch": "deny",
            },
        }
    },
}
print(json.dumps(config))
PY
)"

exec env HERDR_ROLE=supervisor OPENCODE_CONFIG_CONTENT="$config" \
  "${OPENCODE_BIN:-${HOME}/.opencode/bin/opencode}" \
  --agent herdr-supervisor \
  --auto \
  "$@"
