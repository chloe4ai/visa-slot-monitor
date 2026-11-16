#!/usr/bin/env bash
# Create a fresh state file at the path named in config.json.
set -euo pipefail
CONFIG="${1:-config.json}"
[ -f "$CONFIG" ] || { echo "No $CONFIG. Copy config.example.json and fill it in." >&2; exit 1; }
python3 -I - "$CONFIG" <<'PY'
import json, os, sys
cfg = json.load(open(sys.argv[1]))
path = os.path.expanduser(cfg["state_file"])
if os.path.exists(path):
    sys.exit(f"{path} already exists — delete it first if you want a reset.")
json.dump({
    "post": cfg["consular_post"],
    "threshold": cfg["threshold_date"],
    "last_check": None,
    "last_seen_earliest": None,
    "last_seen_available": [],
    "alerted_dates": [],
    "stuck_since": None,
    "holding_tab": None,
    "held_slot": None,
    "held_since": None,
    "held_nag_at": None,
    "blocked_since": None,
    "block_last_alert": None,
    "block_checks": 0,
}, open(path, "w"), indent=2)
print(f"wrote {path}")
PY
