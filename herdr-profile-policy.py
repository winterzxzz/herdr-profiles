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

ROLES = {"orchestrator", "implementer", "peer", "supervisor"}

# A goal makes the runtime re-enter the thread on its own schedule until the
# objective is met. Inside a room with live seats that is a context-burning
# self-poll, so no role may touch one. Names are speculative on purpose: an
# entry that never appears simply never matches.
GOAL_TOOLS = {"set_goal", "update_goal", "manage_goal", "goal", "goals"}

DELEGATION_TOOLS = {"Agent", "spawn_agent", "task", "Task", "subagent"}

# Codex has no single `Skill` tool the way Claude does: filesystem skills are
# read as ordinary SKILL.md files, and only provider-backed ones go through
# these. Denying them closes the provider path; the filesystem path is closed
# by the instruction ban plus the read-only sandbox on non-implementer roles.
SKILL_TOOLS = {"Skill", "skill", "skills.list", "skills.read", "skills"}

# The supervisor observes the room and reports; it never changes it. Only these
# `herdr <group> <subcommand>` pairs are reachable, so a mutating command such
# as `agent start`, `pane run`, or `pane close` is denied even though the same
# group is allowed for reads. `notification show` is its report channel: it
# surfaces findings to the user without touching topology.
SUPERVISOR_HERDR = {
    ("agent", "list"),
    ("agent", "get"),
    ("agent", "read"),
    ("agent", "explain"),
    ("pane", "list"),
    ("pane", "get"),
    ("pane", "read"),
    ("pane", "current"),
    ("pane", "layout"),
    ("pane", "process-info"),
    ("api", "snapshot"),
    ("workspace", "list"),
    ("tab", "list"),
    ("worktree", "list"),
    ("plugin", "list"),
    ("plugin", "log"),
    ("notification", "show"),
}


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


def supervisor_herdr_command(tokens: list[str]) -> bool:
    """True when tokens are a read-only `herdr <group> <subcommand> ...` call."""
    if len(tokens) < 3:
        return False
    return (tokens[1], tokens[2]) in SUPERVISOR_HERDR


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ROLES:
        deny("Unknown Herdr Codex role; refusing the tool call.")
        return 0

    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        deny("Policy hook received invalid input; refusing the tool call.")
        return 0

    role = sys.argv[1]
    tool = str(event.get("tool_name", ""))

    if tool in DELEGATION_TOOLS:
        deny("Herdr panes are the only delegation mechanism for this profile.")
        return 0

    if tool in SKILL_TOOLS:
        deny("Skills are disabled: they die at compaction and leak room control to seats.")
        return 0

    if tool in GOAL_TOOLS:
        deny("Runtime goals are disabled: they re-enter the thread on a timer and poll the room.")
        return 0

    # The implementer is the one role that may write. Every other role is
    # read-only. This is checked here rather than left to each profile's hook
    # matcher: a matcher that stops listing an edit tool would silently open a
    # hole, whereas this stays closed no matter what reaches the hook.
    if tool in {"apply_patch", "Edit", "Write", "NotebookEdit"} and role != "implementer":
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

    if executable == "herdr":
        # Bare `herdr` launches or attaches the TUI; it is never a control call.
        if len(tokens) < 2:
            deny("Bare `herdr` opens the TUI; use an explicit subcommand.")
            return 0
        if role == "orchestrator":
            return 0
        if role == "supervisor":
            if supervisor_herdr_command(tokens):
                return 0
            deny("The supervisor profile may only read room state, never change it.")
            return 0

    if read_only_command(tokens):
        return 0

    deny(f"Command is outside the {role} profile allowlist.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
