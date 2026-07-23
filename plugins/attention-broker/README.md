# Attention Broker

Wakes the room Lead once when another seat becomes `idle`, `done`, or
`blocked`, so the Lead never has to poll.

Polling is the most expensive habit a Lead can develop: every redundant
`agent wait` / `agent get` / `pane read` spends Lead context on state that has
not changed, and a Lead that compacts mid-run has lost the room. This plugin
inverts the direction — Herdr fires the event, the plugin submits one prompt.

It does not poll, run a model, read project files, or judge a checkpoint. It is
transport.

## Install

```bash
herdr plugin link ~/.herdr-profiles/plugins/attention-broker
herdr plugin list
```

For a named room, target it explicitly:

```bash
herdr --session Fantasy plugin link ~/.herdr-profiles/plugins/attention-broker
```

The plugin finds the Lead by **seat name**. Name the Lead's pane `Lead`:

```bash
herdr pane rename <lead-pane-id> "Lead"
```

## Configure

Optional. Find the config directory with:

```bash
herdr plugin config-dir local.herdr-attention-broker
```

`config.json`:

```json
{
  "lead_name": "Lead",
  "dedupe_window_ms": 5000,
  "supervisor_name": "Supervisor",
  "supervisor_min_interval_ms": 60000
}
```

`root_name` is accepted as an alias for `lead_name` so configs written against
the original prototype keep working.

## Inspect

```bash
herdr plugin action invoke local.herdr-attention-broker.status
herdr plugin log list --plugin local.herdr-attention-broker
```

## Waking the Supervisor

If a seat named `Supervisor` exists, room events wake it too, with a
`HERDR_SWEEP` line. It has no other way to run: it holds no timer, no sleep,
and no runtime goal, so without a push it sweeps once at launch and then idles
forever.

Three rules keep that from becoming noise:

- **Throttled**, default 60s. A sweep re-reads the whole room, so it is
  idempotent and a missed one costs nothing — the next event triggers another.
  That is why supervisor wakes are dropped rather than queued.
- **Never woken by its own events.** Waking it makes it run commands, which
  flips its status, which fires another event. Without the self-check the
  plugin livelocks.
- **Its lifecycle never reaches the Lead.** The Lead does not own the
  Supervisor and collects no handback from it, and the Supervisor cycles
  working/idle on every sweep — queueing those would flood the Lead with
  exactly the attention noise this plugin removes.

## Behaviour

- **Persists before delivering.** A failed `pane run` leaves the event queued;
  delivery is retried the next time the Lead reports `idle` or `done`.
- **Deduplicates** identical `event:workspace:pane:status` signatures inside the
  configured window.
- **Namespaces state by session socket**, so linked rooms cannot deduplicate or
  deliver one another's events even when their workspace and pane IDs overlap.
- **Locks** state with an atomic `mkdir`, reclaiming a lock older than 30s.

## Differences from the upstream prototype

This is derived from the Herdr author's `attention-broker` prototype, with
three changes:

1. **macOS support.** The original declared `platforms = ["linux"]`, so it never
   loaded on Darwin.

2. **Seat names are sanitized before they reach the Lead's prompt.** Seat names
   come from `pane rename` and are user-controlled; the original interpolated
   them straight into the text submitted via `pane run`. Renaming a pane could
   therefore put arbitrary text — including instructions, on their own line —
   into the Lead's input as though the room had said it. Names are now
   restricted to an identifier charset and capped at 48 characters.

3. **Events are queued, not dropped, when the Lead is unresolvable.** The
   original exited `0` in silence whenever it did not find exactly one matching
   seat, which turns a misnamed pane into a Lead that waits forever for a wake
   that was never queued. Unresolvable events now go to a holding queue, log a
   warning, and are adopted by the Lead as soon as one appears.
