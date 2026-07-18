#!/usr/bin/env python3
"""Fail-closed PreToolUse policy shared by the three Codex profiles."""

from __future__ import annotations

import json
import re
import shlex
import sys
from typing import Any


READ_ONLY_GIT = {"status", "log", "diff", "show", "branch"}
READ_ONLY_COMMANDS = {"cat", "grep", "jq", "ls", "pwd", "rg", "test", "wc"}
SHELL_META = re.compile(r"[><|;&`\r\n]|\$\(")


def deny(reason: str) -> None:
    payload = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(payload))


def command_tokens(tool_input: dict[str, Any]) -> list[str] | None:
    command = tool_input.get("command")
    if isinstance(command, list):
        command = " ".join(str(part) for part in command)
    if not isinstance(command, str) or not command.strip():
        return None
    if SHELL_META.search(command):
        return None
    try:
        return shlex.split(command)
    except ValueError:
        return None


def read_only_command(tokens: list[str]) -> bool:
    if not tokens:
        return False
    executable = tokens[0].rsplit("/", 1)[-1]
    if executable in READ_ONLY_COMMANDS:
        return True
    if executable != "git" or len(tokens) < 2:
        return False
    if tokens[1] in READ_ONLY_GIT:
        return True
    return tokens[1:4] == ["worktree", "list"]


def contains_command(tokens: list[str], executable: str, subcommand: str | None = None) -> bool:
    for index, token in enumerate(tokens):
        if token.rsplit("/", 1)[-1] != executable:
            continue
        if subcommand is None:
            return True
        if subcommand in tokens[index + 1 :]:
            return True
    return False


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"orchestrator", "implementer", "peer"}:
        deny("Unknown Herdr Codex role; refusing the tool call.")
        return 0

    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        deny("Policy hook received invalid input; refusing the tool call.")
        return 0

    role = sys.argv[1]
    tool = str(event.get("tool_name", ""))

    if tool in {"Agent", "spawn_agent"}:
        deny("Herdr panes are the only delegation mechanism for this profile.")
        return 0

    if tool in {"apply_patch", "Edit", "Write"}:
        deny(f"The {role} profile is read-only.")
        return 0

    if tool != "Bash":
        return 0

    tokens = command_tokens(event.get("tool_input", {}))
    if tokens is None:
        deny("Compound commands, shell metacharacters, and invalid commands are not allowed.")
        return 0

    executable = tokens[0].rsplit("/", 1)[-1]
    if role == "implementer":
        if contains_command(tokens, "herdr"):
            deny("The implementer profile cannot control Herdr.")
        elif contains_command(tokens, "git", "push"):
            deny("The implementer profile cannot push; leave publication to the user.")
        return 0

    if role == "orchestrator" and executable == "herdr" and len(tokens) > 1:
        return 0
    if read_only_command(tokens):
        return 0

    deny(f"Command is outside the {role} profile allowlist.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
