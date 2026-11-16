#!/usr/bin/env bash
# Render prompts/monitor-run.md with values from config.json.
# Usage: ./render.sh [config.json] > run-prompt.txt
set -euo pipefail
CONFIG="${1:-config.json}"
[ -f "$CONFIG" ] || { echo "No $CONFIG. Copy config.example.json and fill it in." >&2; exit 1; }
python3 -I - "$CONFIG" <<'PY'
import json, re, sys, pathlib
cfg = json.load(open(sys.argv[1]))
tpl = pathlib.Path("prompts/monitor-run.md").read_text()
tpl = tpl.split("---\n", 1)[1]
MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
views = "; ".join(
    f"{v['year']} {v['month']}" + (" (PRIORITY)" if v.get("priority") else "")
    for v in cfg["scan_views"]
)
first = min(cfg["scan_views"], key=lambda v: (v["year"], MONTHS.index(v["month"])))
scan_from = f'{first["year"]}, {MONTHS.index(first["month"])}, 1'
ty, tm, td = (int(x) for x in cfg["threshold_date"].split("-"))
scan_to = f"{ty}, {tm - 1}, {td}"
vals = {
    "SITE_URL": cfg["site_url"],
    "CONSULAR_POST": cfg["consular_post"],
    "APPLICANT_NAME": cfg["applicant_name"],
    "THRESHOLD_DATE": cfg["threshold_date"],
    "NOTIFY_EMAIL": cfg["notify_email"],
    "STATE_FILE": cfg["state_file"],
    "STUCK_REALERT_HOURS": str(cfg["stuck_realert_hours"]),
    "SCAN_VIEWS": views,
    "SCAN_FROM": scan_from,
    "SCAN_TO": scan_to,
}
missing = set(re.findall(r"\{\{(\w+)\}\}", tpl)) - set(vals)
if missing:
    sys.exit(f"config.json is missing: {', '.join(sorted(missing))}")
for k, v in vals.items():
    tpl = tpl.replace("{{%s}}" % k, v)
print(tpl)
PY
