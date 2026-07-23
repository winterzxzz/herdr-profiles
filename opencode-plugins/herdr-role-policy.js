// herdr-role-policy — enforce read-only room roles in opencode.
//
// Why a plugin instead of permission rules:
//
//   opencode's bash permissions are glob patterns matched against the whole
//   command string, and `*` is greedy. An allow rule for "herdr agent read *"
//   therefore also matches:
//
//       herdr agent read impl-auth && herdr pane close wA:p2
//
//   which is exactly the mutation the rule exists to prevent. The Codex policy
//   hook rejects shell metacharacters before allow-listing; nothing in the glob
//   engine can express that. This plugin restores parity: it tokenizes the
//   command, refuses anything containing shell metacharacters, and checks the
//   result against an explicit (group, subcommand) allowlist.
//
// Scope: the wrapper sets HERDR_ROLE. With no role set the plugin is inert, so
// ordinary opencode sessions are untouched.

const READ_ONLY_COMMANDS = new Set(["cat", "grep", "jq", "ls", "pwd", "rg", "test", "wc"]);
const READ_ONLY_GIT = new Set(["status", "log", "diff", "show", "branch"]);

// Read-only `herdr <group> <subcommand>` pairs. `notification show` is the
// supervisor's report channel: it reaches the human without touching topology.
const SUPERVISOR_HERDR = new Set([
  "agent list",
  "agent get",
  "agent read",
  "agent explain",
  "pane list",
  "pane get",
  "pane read",
  "pane current",
  "pane layout",
  "pane process-info",
  "api snapshot",
  "workspace list",
  "tab list",
  "worktree list",
  "plugin list",
  "plugin log",
  "notification show",
]);

// Anything that can chain, redirect, substitute, or span lines. Denied outright
// rather than parsed: an allowlist is only meaningful if one command string
// cannot smuggle a second command.
const SHELL_META = /[><|;&`\r\n]|\$\(/;

export const HerdrRolePolicyPlugin = async ({ client }) => {
  const role = process.env.HERDR_ROLE;
  if (role !== "supervisor") {
    return {};
  }

  const log = (message, extra) =>
    client?.app
      ?.log({ body: { service: "herdr-role-policy", level: "warn", message, extra } })
      ?.catch?.(() => {});

  const refuse = (reason, extra) => {
    log(reason, extra);
    throw new Error(`[herdr:${role}] ${reason}`);
  };

  return {
    "tool.execute.before": async (input, output) => {
      const tool = typeof input?.tool === "string" ? input.tool.toLowerCase() : "";

      if (["edit", "write", "patch", "task", "skill", "todowrite"].includes(tool)) {
        refuse(`The ${role} profile observes the room; it never changes it.`, { tool });
      }

      if (tool !== "bash") return;

      const command = String(output?.args?.command ?? "");
      if (!command.trim()) return;

      if (SHELL_META.test(command)) {
        refuse("Compound commands and shell metacharacters are not allowed.", { command });
      }

      const tokens = command.trim().split(/\s+/);
      const executable = tokens[0].split("/").pop();

      if (executable === "herdr") {
        const pair = `${tokens[1] ?? ""} ${tokens[2] ?? ""}`.trim();
        if (!SUPERVISOR_HERDR.has(pair)) {
          refuse(`The ${role} profile may only read room state, never change it.`, { command });
        }
        return;
      }

      if (READ_ONLY_COMMANDS.has(executable)) return;
      if (executable === "git" && READ_ONLY_GIT.has(tokens[1])) return;
      if (executable === "git" && tokens[1] === "worktree" && tokens[2] === "list") return;

      refuse(`Command is outside the ${role} profile allowlist.`, { command });
    },
  };
};
