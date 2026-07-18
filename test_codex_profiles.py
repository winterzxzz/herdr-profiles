#!/usr/bin/env python3
"""Regression tests for the Codex profile files and policy hook."""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tomllib
import unittest


ROOT = pathlib.Path(__file__).resolve().parent
POLICY = ROOT / "herdr-profile-policy.py"


def policy(role: str, tool: str, command: str = "") -> dict[str, object]:
    event = {"tool_name": tool, "tool_input": {"command": command}}
    completed = subprocess.run(
        [sys.executable, str(POLICY), role],
        input=json.dumps(event),
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(completed.stdout) if completed.stdout else {}


class CodexProfileTests(unittest.TestCase):
    def test_profile_toml_is_valid(self) -> None:
        for path in ROOT.glob("codex-*.config.toml"):
            with self.subTest(path=path.name):
                tomllib.loads(path.read_text(encoding="utf-8"))

    def test_orchestrator_policy(self) -> None:
        self.assertEqual(policy("orchestrator", "Bash", "herdr pane list"), {})
        self.assertEqual(policy("orchestrator", "Bash", "git diff --stat"), {})
        self.assertIn("hookSpecificOutput", policy("orchestrator", "apply_patch"))
        self.assertIn("hookSpecificOutput", policy("orchestrator", "Bash", "cat x > y"))

    def test_implementer_policy(self) -> None:
        self.assertEqual(policy("implementer", "Bash", "npm test"), {})
        self.assertIn("hookSpecificOutput", policy("implementer", "Bash", "herdr pane list"))
        self.assertIn("hookSpecificOutput", policy("implementer", "Bash", "env herdr pane list"))
        self.assertIn("hookSpecificOutput", policy("implementer", "Bash", "git push origin main"))
        self.assertIn("hookSpecificOutput", policy("implementer", "Bash", "command git push"))
        self.assertIn("hookSpecificOutput", policy("implementer", "Bash", "git -C /tmp push"))
        self.assertIn("hookSpecificOutput", policy("implementer", "Agent"))

    def test_peer_policy(self) -> None:
        self.assertEqual(policy("peer", "Bash", "git show HEAD"), {})
        self.assertEqual(policy("peer", "Bash", "rg TODO src"), {})
        self.assertIn("hookSpecificOutput", policy("peer", "Bash", "rm -rf build"))
        self.assertIn("hookSpecificOutput", policy("peer", "spawn_agent"))


if __name__ == "__main__":
    unittest.main()
