#!/usr/bin/env bash
# Holistic plan ID + ledger validator (HOLISTIC #020).
#
# Checks docs/HOLISTIC_FINISHING_PLAN_400.md for duplicate/missing IDs in the
# authored range 001–160, and that checked tasks have a ledger entry in
# docs/HOLISTIC_FINISHING_LEDGER.md. Also flags completed tasks whose
# explicit prerequisite IDs lack ledger evidence.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAN="$ROOT/docs/HOLISTIC_FINISHING_PLAN_400.md"
LEDGER="$ROOT/docs/HOLISTIC_FINISHING_LEDGER.md"
MAX_ID="${HOLISTIC_VALIDATE_MAX:-160}"

if [[ ! -f "$PLAN" || ! -f "$LEDGER" ]]; then
	echo "validate_holistic_plan: missing plan or ledger" >&2
	exit 2
fi

python3 - "$PLAN" "$LEDGER" "$MAX_ID" <<'PY'
import re, sys
from pathlib import Path

plan_path, ledger_path, max_id_s = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
max_id = int(max_id_s)
plan = plan_path.read_text()
ledger = ledger_path.read_text()

task_re = re.compile(r"^- \[([ xX])\] \*\*(\d{3})\b")
prereq_re = re.compile(r"\*\*(\d{3})\b.*?Depends?:\s*([0-9,\s]+)", re.I)
# Also catch inline "requires 001" style near the task line — keep light.
inline_dep = re.compile(r"\*\*(\d{3})\b[^\n]{0,200}?\b(?:requires?|prereq(?:uisites?)?|depends? on)\s+((?:\d{3}(?:\s*,\s*)?)+)", re.I)

ids = []
checked = []
deps = {}
for line in plan.splitlines():
    m = task_re.match(line)
    if not m:
        continue
    mark, tid = m.group(1), m.group(2)
    ids.append(tid)
    if mark.strip().lower() == "x":
        checked.append(tid)
    dm = inline_dep.search(line)
    if dm:
        deps[tid] = re.findall(r"\d{3}", dm.group(2))

# Ledger mentions of task IDs: table rows "| 001 |" or bare "001" in Status tables.
ledger_ids = set(re.findall(r"(?:^\|\s*|batch[^|]*\|\s*)(\d{3})\s*\|", ledger, re.M | re.I))
ledger_ids |= set(re.findall(r"\|\s*(\d{3})\s*\|\s*(?:implemented|verified-existing|deferred|rejected)\s*\|", ledger, re.I))
# Also accept headings / prose "task 001" / "| 001 |"
ledger_ids |= set(re.findall(r"\b(\d{3})\b", ledger))

errors = []
# Duplicates
seen = {}
for tid in ids:
    seen[tid] = seen.get(tid, 0) + 1
for tid, n in sorted(seen.items()):
    if n > 1:
        errors.append(f"duplicate task ID {tid} ({n} times)")

# Missing in 001..MAX among authored checklist IDs that claim that range
present = set(ids)
expected = {f"{i:03d}" for i in range(1, max_id + 1)}
# Only flag missing if the plan authors the range (has 001 and near-max)
if "001" in present:
    missing = sorted(expected - present)
    # Allow incomplete expansion past the last authored ID
    if present:
        authored_max = max(int(x) for x in present)
        missing = [m for m in missing if int(m) <= min(max_id, authored_max)]
    for m in missing:
        errors.append(f"missing task ID {m} in plan checklist")

# Checked without ledger evidence
for tid in checked:
    if tid not in ledger_ids:
        errors.append(f"checked task {tid} has no ledger entry in HOLISTIC_FINISHING_LEDGER.md")

# Explicit deps of checked tasks must have ledger evidence
for tid in checked:
    for dep in deps.get(tid, []):
        if dep not in ledger_ids:
            errors.append(f"checked task {tid} depends on {dep}, which lacks ledger evidence")

print(f"validate_holistic_plan: tasks={len(ids)} checked={len(checked)} ledger_hits={len(ledger_ids)} range=001-{max_id:03d}")
if errors:
    print("FAIL:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)
print("OK")
PY
