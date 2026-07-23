// herdr-no-subagent — hard-block opencode subagent spawning.
//
// This lives BESIDE ~/.config/opencode/plugins/herdr-agent-state.js, never
// inside it: that file is herdr-managed and is overwritten by
// `herdr integration install opencode`.
//
// Why a plugin and not config:
//
//   `agent.<name>.permission.task = "deny"` only covers agents defined in a
//   config this session actually loaded. opencode always merges the global
//   ~/.config/opencode/opencode.json, a project config can re-enable the tool,
//   and any agent you did not author (or a future default) is unprotected.
//   `tool.execute.before` runs for every session regardless of which agent,
//   config layer, or CLI flag is in play, and throwing there aborts the call.
//
// Why blocking matters here: a Herdr room's core invariant is that panes are
// the only personnel mechanism. A seat that spawns its own subagents creates
// owners the Lead cannot see, wait on, or close — the room topology stops
// matching reality and the single-writer guarantee is gone.
//
// Escape hatch: set OPENCODE_ALLOW_TASK=1 for a session that genuinely needs
// subagents. Deliberate and per-session, never the default.

const BLOCKED_TOOLS = new Set(["task", "subagent", "spawn_agent", "agent"]);

const REASON =
  "Subagents are disabled. Delegation goes through Herdr panes so every " +
  "owner is visible to the Lead. Set OPENCODE_ALLOW_TASK=1 to override.";

export const HerdrNoSubagentPlugin = async ({ client }) => {
  if (process.env.OPENCODE_ALLOW_TASK === "1") {
    return {};
  }

  const log = (level, message, extra) =>
    client?.app
      ?.log({ body: { service: "herdr-no-subagent", level, message, extra } })
      // Logging must never be the reason a tool call succeeds.
      ?.catch?.(() => {});

  return {
    "tool.execute.before": async (input) => {
      const tool = typeof input?.tool === "string" ? input.tool.toLowerCase() : "";
      if (!BLOCKED_TOOLS.has(tool)) return;

      log("warn", "blocked subagent spawn", {
        tool: input.tool,
        sessionID: input.sessionID,
      });
      throw new Error(REASON);
    },
  };
};
