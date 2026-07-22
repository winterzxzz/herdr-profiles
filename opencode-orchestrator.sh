#!/usr/bin/env bash
# opencode root orchestrator. Edit and subagent delegation are blocked by the
# agent permission config; Herdr remains the only delegation mechanism.
set -euo pipefail

PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${HERDR_ENV:-}" != "1" ]]; then
  printf 'opencode-orchestrator.sh must run inside a Herdr-managed pane.\n' >&2
  exit 1
fi

# Build inline config at runtime so herdr-instructions.md changes take effect
# immediately without reinstalling. OPENCODE_CONFIG_CONTENT is loaded after
# project configs in the precedence chain, so it wins over project overrides.
config="$(python3 - "$PROFILE_DIR/herdr-instructions.md" <<'PY'
import json
import pathlib
import sys

instructions = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")

config = {
    "$schema": "https://opencode.ai/config.json",
    "agent": {
        "herdr-orchestrator": {
            "mode": "primary",
            "hidden": True,
            "model": "openrouter/deepseek/deepseek-v4-flash:free",
            "variant": "high",
            "description": "Herdr root orchestrator — delegates via herdr CLI only",
            # prompt lands in the system-prompt layer, survives context compaction.
            "prompt": instructions,
            "permission": {
                # Deny everything by default; specific allows follow (last match wins).
                "*": "deny",
                "read": "allow",
                "glob": "allow",
                "grep": "allow",
                "list": "allow",
                "lsp": "allow",
                "bash": {
                    "*": "deny",
                    "git status": "allow",
                    "git status *": "allow",
                    "git log": "allow",
                    "git log *": "allow",
                    "git diff": "allow",
                    "git diff *": "allow",
                    "git show *": "allow",
                    "git worktree list": "allow",
                    "cat *": "allow",
                    "ls": "allow",
                    "ls *": "allow",
                    "grep *": "allow",
                    "rg *": "allow",
                    "echo *": "allow",
                    "test *": "allow",
                    # herdr * (with at least one arg) — bare "herdr" opens TUI, deny it.
                    "herdr *": "allow",
                },
                "edit": "deny",
                "task": "deny",
                "todowrite": "deny",
                "webfetch": "deny",
                "websearch": "deny",
                "skill": "deny",
            },
        }
    },
}
print(json.dumps(config))
PY
)"

exec env OPENCODE_CONFIG_CONTENT="$config" \
  "${OPENCODE_BIN:-${HOME}/.opencode/bin/opencode}" \
  --agent herdr-orchestrator \
  --auto \
  "$@"
