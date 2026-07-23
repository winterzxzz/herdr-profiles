#!/usr/bin/env bash
# Strip per-model subagent activation from the Codex model catalog cache.
#
# Why this exists: `[features] multi_agent = false` in a profile does NOT
# disable subagents on sol-family models. Each model entry in the cached
# catalog carries its own `multi_agent_version` key ("v2" for gpt-5.6-sol and
# gpt-5.6-terra, "v1" for gpt-5.6-luna), and that per-model value wins over the
# feature flag. Older models (gpt-5.5, gpt-5.4, ...) simply have no such key,
# which is the state this script reproduces.
#
# The catalog is a CACHE. The cockpit local-access service refetches it, which
# restores `multi_agent_version`. Re-run this after any Codex update, cockpit
# restart, or model refresh, and check with `--check` if a subagent ever
# appears where it should not.
#
#   ./patch-model-cache.sh            # patch (idempotent)
#   ./patch-model-cache.sh --check    # report state, exit 1 if any model armed
#   ./patch-model-cache.sh --restore  # put the pristine catalog back
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CATALOG="$CODEX_HOME/cockpit-local-access-model-catalog.json"
BACKUP="$CATALOG.pre-herdr.bak"
MODE="${1:---patch}"

if [[ ! -f "$CATALOG" ]]; then
  printf 'model catalog not found: %s\n' "$CATALOG" >&2
  printf 'Nothing to patch. Codex may not have fetched a catalog yet.\n' >&2
  exit 1
fi

case "$MODE" in
  --patch|--check|--restore) ;;
  -h|--help)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    printf 'unknown mode: %s (use --patch, --check, or --restore)\n' "$MODE" >&2
    exit 1
    ;;
esac

if [[ "$MODE" == "--restore" ]]; then
  if [[ ! -f "$BACKUP" ]]; then
    printf 'no pristine backup at %s\n' "$BACKUP" >&2
    exit 1
  fi
  cp -- "$BACKUP" "$CATALOG"
  printf 'restored pristine catalog from %s\n' "$BACKUP"
  exit 0
fi

KEY="multi_agent_version" CATALOG="$CATALOG" BACKUP="$BACKUP" MODE="$MODE" \
python3 - <<'PY'
import json
import os
import pathlib
import shutil
import sys
import tempfile

key = os.environ["KEY"]
catalog = pathlib.Path(os.environ["CATALOG"])
backup = pathlib.Path(os.environ["BACKUP"])
check_only = os.environ["MODE"] == "--check"

try:
    data = json.loads(catalog.read_text(encoding="utf-8"))
except json.JSONDecodeError as error:
    sys.exit(f"catalog is not valid JSON ({error}); refusing to touch it")

models = data.get("models")
if not isinstance(models, list) or not models:
    sys.exit("catalog has no 'models' list; refusing to touch it")

armed = [m for m in models if m.get(key) is not None]

if check_only:
    for model in models:
        slug = model.get("slug", "?")
        value = model.get(key)
        state = f"subagent={value}" if value is not None else "subagent=off"
        print(f"{slug:24} {state}")
    if armed:
        print(f"\n{len(armed)} model(s) still arm subagents. Run without --check.")
        sys.exit(1)
    print("\nall models have subagents disabled")
    sys.exit(0)

if not armed:
    print("already patched: no model carries a subagent version")
    sys.exit(0)

# Keep exactly one pristine copy. Never overwrite it on a later run, or a
# second patch would back up the already-patched file and lose the original.
if not backup.exists():
    shutil.copy2(catalog, backup)
    print(f"pristine catalog saved to {backup}")

for model in armed:
    # Match the shape of models that never had subagents (gpt-5.5 and older):
    # the key is present and null, not absent.
    print(f"  {model.get('slug', '?')}: {key}={model[key]!r} -> None")
    model[key] = None

# Atomic replace so a crash mid-write cannot leave Codex with a truncated
# catalog it will refuse to parse.
handle = tempfile.NamedTemporaryFile(
    "w", encoding="utf-8", dir=str(catalog.parent), delete=False
)
try:
    json.dump(data, handle, ensure_ascii=False)
    handle.flush()
    os.fsync(handle.fileno())
finally:
    handle.close()
os.replace(handle.name, catalog)
shutil.copymode(backup, catalog)

print(f"patched {len(armed)} model(s)")
PY

if [[ "$MODE" == "--patch" ]]; then
  printf '\nRestart any running Codex session; the catalog is read at startup.\n'
fi
