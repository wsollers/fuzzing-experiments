#!/usr/bin/env bash
# opengrep/run_opengrep.sh
# Run OpenGrep (or Semgrep) security rules against Doom 3 BFG source.
# Output: reports/opengrep_results.json  +  reports/opengrep_summary.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${ROOT_DIR}/src/doom-3-bfg/neo"
RULES_DIR="${SCRIPT_DIR}/rules"
REPORTS_DIR="${ROOT_DIR}/reports"
JSON_OUT="${REPORTS_DIR}/opengrep_results.json"
MD_OUT="${REPORTS_DIR}/opengrep_summary.md"

mkdir -p "${REPORTS_DIR}"

if ! command -v opengrep &>/dev/null && ! command -v semgrep &>/dev/null; then
  echo "[OpenGrep] Neither opengrep nor semgrep found. Install via: pip install opengrep-cli" >&2
  exit 1
fi

GREP_CMD="opengrep"
command -v opengrep &>/dev/null || GREP_CMD="semgrep"

echo "[OpenGrep] Scanning ${SRC_DIR} with ${GREP_CMD}..."
"${GREP_CMD}" \
  --config "${RULES_DIR}" \
  --json \
  --output "${JSON_OUT}" \
  --no-git-ignore \
  "${SRC_DIR}" || true   # non-zero exit when findings present is normal

echo "[OpenGrep] Generating Markdown summary..."
python3 - <<'PYEOF'
import json, pathlib, collections, datetime

json_path  = "${JSON_OUT}"
md_path    = "${MD_OUT}"

with open(json_path) as f:
    data = json.load(f)

results = data.get("results", [])
counts  = collections.Counter(r["check_id"] for r in results)

lines = [
    "# OpenGrep Security Scan Summary",
    "",
    f"**Generated:** {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}",
    f"**Target:** `src/doom-3-bfg/neo`",
    f"**Total findings:** {len(results)}",
    "",
    "## Findings by Rule",
    "",
    "| Rule ID | Severity | Count |",
    "|---------|----------|------:|",
]

sev_map = {r["check_id"]: r.get("extra", {}).get("severity", "?") for r in results}
for rule_id, cnt in sorted(counts.items(), key=lambda x: -x[1]):
    lines.append(f"| `{rule_id}` | {sev_map.get(rule_id,'?')} | {cnt} |")

lines += [
    "",
    "## All Findings",
    "",
    "| # | Rule | File | Line | Message |",
    "|---|------|------|-----:|---------|",
]

for i, r in enumerate(results, 1):
    rule   = r.get("check_id", "")
    path   = r.get("path", "")
    start  = r.get("start", {}).get("line", "?")
    msg    = r.get("extra", {}).get("message", "")[:100].replace("\n", " ")
    lines.append(f"| {i} | `{rule}` | `{path}` | {start} | {msg} |")

pathlib.Path(md_path).write_text("\n".join(lines) + "\n")
print(f"[OpenGrep] Wrote {len(results)} findings to {md_path}")
PYEOF

echo "[OpenGrep] Done."
