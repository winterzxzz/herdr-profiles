#!/usr/bin/env node

// Wake the room Lead once when another seat becomes idle, done, or blocked.
//
// This exists to delete polling. A Lead that loops on `herdr agent wait`
// burns its own context reading unchanged state, and a Lead that has compacted
// mid-run has lost the room. Here the runtime pushes instead: Herdr fires the
// event, this script queues it durably and submits one prompt to the Lead.
//
// It does not poll, run a model, read project files, or judge a checkpoint.
// It is transport.
//
// Derived from the attention-broker prototype by the Herdr author, with three
// changes: macOS support, seat names sanitized before they reach the Lead's
// prompt, and events queued rather than dropped when the Lead is unresolvable.

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawnSync } = require("node:child_process");

const mode = process.argv[2] ?? "event";
const stateDir = process.env.HERDR_PLUGIN_STATE_DIR;
const configDir = process.env.HERDR_PLUGIN_CONFIG_DIR;
const herdr = process.env.HERDR_BIN_PATH ?? "herdr";
const socketPath = process.env.HERDR_SOCKET_PATH;

if (!stateDir || !configDir || !socketPath) {
  fail("attention-broker must run through Herdr's plugin runtime.");
}

fs.mkdirSync(stateDir, { recursive: true });
fs.mkdirSync(configDir, { recursive: true });

// Namespace state by session socket so linked rooms cannot deduplicate or
// deliver one another's events even when their workspace and pane IDs overlap.
const sessionKey = crypto.createHash("sha256").update(socketPath).digest("hex").slice(0, 16);
const sessionStateDir = path.join(stateDir, "sessions", sessionKey);
fs.mkdirSync(sessionStateDir, { recursive: true });
const statePath = path.join(sessionStateDir, "state.json");
const lockPath = path.join(sessionStateDir, "state.lock");

const config = readJson(path.join(configDir, "config.json"), {});
const leadName = stringValue(config.lead_name) ?? stringValue(config.root_name) ?? "Lead";
const dedupeWindowMs = positiveInteger(config.dedupe_window_ms) ?? 5000;

// The Supervisor audits the room but has no way to pace itself: it holds no
// timer, no sleep, and no runtime goal (goals are banned room-wide because they
// re-enter a thread on the runtime's schedule). Without a push it runs exactly
// one sweep at launch and then idles forever. So the same event that wakes the
// Lead also wakes the Supervisor — throttled, because a busy room fires far
// more status changes than an audit needs.
const supervisorName = stringValue(config.supervisor_name) ?? "Supervisor";
const supervisorMinIntervalMs = positiveInteger(config.supervisor_min_interval_ms) ?? 60000;

// Events observed while no Lead was resolvable. They are kept rather than
// dropped: a Lead that starts late, or is renamed into place, still gets the
// handbacks it missed.
const ORPHAN_KEY = "__unresolved_lead__";

if (mode === "status") {
  process.stdout.write(
    `${JSON.stringify({ session_key: sessionKey, lead_name: leadName, ...readState() }, null, 2)}\n`,
  );
  process.exit(0);
}

if (mode !== "event") {
  fail(`Unknown mode: ${mode}`);
}

const event = parseEnvJson("HERDR_PLUGIN_EVENT_JSON");
const context = parseEnvJson("HERDR_PLUGIN_CONTEXT_JSON", {});
if (!event || !event.event || !event.data) {
  fail("HERDR_PLUGIN_EVENT_JSON did not contain a Herdr event envelope.");
}
const eventName = stringValue(process.env.HERDR_PLUGIN_EVENT) ?? normalizeEventName(event.event);

const agents = listAgents();
const workspaceId = event.data.workspace_id ?? context.workspace_id;
const eventPaneId = event.data.pane_id ?? context.focused_pane_id;
const leads = agents.filter(
  (agent) => agent.name === leadName && (!workspaceId || agent.workspace_id === workspaceId),
);

const lead = leads.length === 1 ? leads[0] : null;
const supervisors = agents.filter(
  (agent) =>
    agent.name === supervisorName && (!workspaceId || agent.workspace_id === workspaceId),
);
const supervisor = supervisors.length === 1 ? supervisors[0] : null;
const subject = agents.find((agent) => agent.pane_id === eventPaneId);
const subjectAgent =
  stringValue(event.data.agent) ??
  stringValue(subject?.agent) ??
  stringValue(context.focused_pane_agent);
const subjectName = stringValue(subject?.name);
const status = stringValue(event.data.agent_status) ?? stringValue(subject?.agent_status);
const leadEvent = Boolean(lead) && eventPaneId === lead.pane_id;

note(
  `${eventName} pane=${safe(eventPaneId)} status=${safe(status ?? "none")} ` +
    `subject=${safe(subjectName ?? subjectAgent ?? "unknown")} ` +
    `lead=${lead ? safe(lead.name) : "unresolved"}`,
);

if (!lead) {
  // Loud, not silent. A misnamed or missing Lead is a room-configuration bug,
  // and the original prototype's silent exit(0) made it invisible: the Lead
  // simply waited forever for a wake that was never queued.
  note(
    `WARNING: expected exactly one seat named "${leadName}" in this workspace, found ` +
      `${leads.length}. Queueing for later delivery. Rename the Lead's pane, or set ` +
      `lead_name in the plugin config.json.`,
  );
}

withStateLock(() => {
  const state = readState();
  pruneRecent(state, Date.now());

  try {
    handleEvent(state);
  } finally {
    // Runs on every path, including the early returns above: any room activity
    // is a reason for the Supervisor to look, not just activity that produced a
    // Lead handback.
    wakeSupervisor(state);
    writeState(state);
  }
});

function handleEvent(state) {
  if (leadEvent) {
    // The Lead itself reached a boundary — a good moment to deliver anything
    // that failed to submit while it was busy.
    if (status === "idle" || status === "done") {
      flushLead(state, lead);
    }
    return;
  }

  // The Supervisor is not one of the Lead's seats: the Lead neither owns its
  // lifecycle nor collects handbacks from it. It also cycles working/idle on
  // every sweep, so queueing its transitions would flood the Lead with exactly
  // the attention noise this plugin exists to remove.
  if (supervisor && eventPaneId === supervisor.pane_id) {
    note("ignored supervisor lifecycle event");
    return;
  }

  if (!shouldQueue(eventName, status, subjectAgent)) {
    return;
  }

  const signature = [eventName, workspaceId, eventPaneId, status ?? "none"].join(":");
  const now = Date.now();
  if (state.recent[signature] && now - state.recent[signature] < dedupeWindowMs) {
    note(`deduplicated ${signature}`);
    return;
  }
  state.recent[signature] = now;

  // Persist before delivery. A failed `pane run` must leave the event queued,
  // never lost.
  const key = lead ? lead.terminal_id : ORPHAN_KEY;
  state.pending[key] ??= [];
  state.pending[key].push({
    signature,
    event: eventName,
    workspace_id: workspaceId,
    pane_id: eventPaneId,
    agent: subjectAgent,
    name: subjectName,
    status: status ?? terminalReason(eventName),
    observed_at: new Date(now).toISOString(),
  });

  if (lead) flushLead(state, lead);
}

// A sweep re-reads the whole room, so it is idempotent and a missed one costs
// nothing — the next event triggers another. That is why this throttles and
// drops rather than queueing the way Lead handbacks do.
function wakeSupervisor(state) {
  if (!supervisor) return;

  // Without this the plugin livelocks: waking the Supervisor makes it run
  // commands, which flips its own status, which fires another event, which
  // wakes it again.
  if (eventPaneId === supervisor.pane_id) return;

  // Keyed per seat, not per session. State is namespaced by socket, so a single
  // scalar would let a busy workspace starve the Supervisor of every other
  // workspace sharing this Herdr session.
  const now = Date.now();
  const last = Number.isFinite(state.supervisor_woke_at[supervisor.terminal_id])
    ? state.supervisor_woke_at[supervisor.terminal_id]
    : 0;
  const waited = now - last;
  if (waited < supervisorMinIntervalMs) {
    note(`supervisor throttled (${Math.round((supervisorMinIntervalMs - waited) / 1000)}s left)`);
    return;
  }

  const prompt =
    `HERDR_SWEEP ${safe(subjectName ?? subjectAgent ?? "room")}:${safe(status ?? "changed")}. ` +
    "Run one audit sweep now. Report only findings that are new or worse than your " +
    "last sweep, through herdr notification show. If the room is healthy, report " +
    "nothing and end the turn. Do not poll; the next room event will wake you.";

  const result = runHerdr(["pane", "run", supervisor.pane_id, prompt]);
  if (result.status !== 0) {
    note(`supervisor wake failed: ${result.stderr.trim()}`);
    return;
  }
  state.supervisor_woke_at[supervisor.terminal_id] = now;
  note(`woke ${safe(supervisor.name)}`);
}

function shouldQueue(eventName, agentStatus, agentLabel) {
  if (eventName === "pane.agent_status_changed") {
    return Boolean(agentLabel) && ["idle", "done", "blocked"].includes(agentStatus);
  }
  return Boolean(agentLabel) && ["pane.exited", "pane.closed"].includes(eventName);
}

function flushLead(state, lead) {
  // Adopt anything queued while no Lead was resolvable.
  if (state.pending[ORPHAN_KEY]?.length) {
    state.pending[lead.terminal_id] ??= [];
    state.pending[lead.terminal_id].push(...state.pending[ORPHAN_KEY]);
    note(`adopted ${state.pending[ORPHAN_KEY].length} orphaned event(s)`);
    delete state.pending[ORPHAN_KEY];
  }

  const pending = state.pending[lead.terminal_id] ?? [];
  if (pending.length === 0) return;

  const summary = pending.map((item) => `${seatLabel(item)}:${safe(item.status)}`).join(", ");
  const prompt =
    `HERDR_ATTENTION_EVENT ${summary}. ` +
    "Consume the current handback or lifecycle gate once. Do not launch a polling loop; " +
    "re-arm attention only after making the next supervision decision.";

  const result = runHerdr(["pane", "run", lead.pane_id, prompt]);
  if (result.status !== 0) {
    // Stay queued. The next time the Lead reports idle or done, delivery is
    // retried from persisted state.
    note(`wake failed for ${lead.name ?? lead.pane_id}: ${result.stderr.trim()}`);
    return;
  }
  delete state.pending[lead.terminal_id];
  note(`woke ${lead.name ?? lead.pane_id} for ${pending.length} event(s)`);
}

function seatLabel(item) {
  return safe(item.name ?? item.agent ?? item.pane_id ?? "unknown-seat");
}

// Seat names are user-controlled: they come from `pane rename`, and this string
// is submitted into the Lead's prompt. Without this, renaming a pane would let
// arbitrary text — including instructions — reach the Lead as if the room had
// said it. Restrict to an identifier-ish charset and cap the length.
function safe(value) {
  const text = typeof value === "string" ? value : String(value ?? "");
  const cleaned = text.replace(/[^\w.@:/-]+/g, "_").slice(0, 48);
  return cleaned || "unknown";
}

function listAgents() {
  const result = runHerdr(["agent", "list"]);
  if (result.status !== 0) {
    fail(`herdr agent list failed: ${result.stderr.trim()}`);
  }
  let parsed;
  try {
    parsed = JSON.parse(result.stdout);
  } catch (error) {
    fail(`herdr agent list returned invalid JSON: ${error.message}`);
  }
  return parsed?.result?.agents ?? [];
}

function runHerdr(args) {
  return spawnSync(herdr, args, {
    encoding: "utf8",
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function readState() {
  const state = readJson(statePath, {});
  return {
    pending: state.pending && typeof state.pending === "object" ? state.pending : {},
    recent: state.recent && typeof state.recent === "object" ? state.recent : {},
    supervisor_woke_at:
      state.supervisor_woke_at && typeof state.supervisor_woke_at === "object"
        ? state.supervisor_woke_at
        : {},
  };
}

function writeState(state) {
  const temp = `${statePath}.${process.pid}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temp, statePath);
}

function withStateLock(callback) {
  const deadline = Date.now() + 2000;
  while (true) {
    try {
      fs.mkdirSync(lockPath);
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      const age = lockAgeMs();
      if (age !== null && age > 30000) {
        fs.rmSync(lockPath, { recursive: true, force: true });
        continue;
      }
      if (Date.now() >= deadline) fail("timed out acquiring the plugin state lock");
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25);
    }
  }
  try {
    callback();
  } finally {
    fs.rmSync(lockPath, { recursive: true, force: true });
  }
}

function lockAgeMs() {
  try {
    return Date.now() - fs.statSync(lockPath).mtimeMs;
  } catch {
    return null;
  }
}

function pruneRecent(state, now) {
  const keepForMs = Math.max(dedupeWindowMs * 12, 60000);
  for (const [key, observedAt] of Object.entries(state.recent)) {
    if (!Number.isFinite(observedAt) || now - observedAt > keepForMs) {
      delete state.recent[key];
    }
  }
}

function parseEnvJson(name, fallback = null) {
  const value = process.env[name];
  if (!value) return fallback;
  try {
    return JSON.parse(value);
  } catch (error) {
    fail(`${name} contained invalid JSON: ${error.message}`);
  }
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return fallback;
    fail(`could not read ${file}: ${error.message}`);
  }
}

function terminalReason(eventName) {
  return eventName === "pane.closed" ? "closed" : "exited";
}

function normalizeEventName(value) {
  const known = {
    pane_agent_status_changed: "pane.agent_status_changed",
    pane_exited: "pane.exited",
    pane_closed: "pane.closed",
  };
  return known[value] ?? value;
}

function stringValue(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function positiveInteger(value) {
  return Number.isInteger(value) && value > 0 ? value : null;
}

function note(message) {
  process.stdout.write(`[attention-broker] ${message}\n`);
}

function fail(message) {
  process.stderr.write(`[attention-broker] ${message}\n`);
  process.exit(1);
}
