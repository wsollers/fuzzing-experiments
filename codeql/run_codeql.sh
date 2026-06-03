#!/usr/bin/env bash
# codeql/run_codeql.sh
# Build CodeQL database for Doom 3 BFG idLib and run all custom queries.
# Output: reports/codeql_results.sarif  +  reports/codeql_summary.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPORTS_DIR="${ROOT_DIR}/reports"
DB_DIR="${ROOT_DIR}/build/codeql_db"
QUERIES_DIR="${SCRIPT_DIR}/queries"
SARIF_OUT="${REPORTS_DIR}/codeql_results.sarif"
SUMMARY_OUT="${REPORTS_DIR}/codeql_summary.md"

mkdir -p "${REPORTS_DIR}" "${DB_DIR}"

echo "[CodeQL] Creating database..."
codeql database create "${DB_DIR}" \
  --language=cpp \
  --command="cmake --build ${ROOT_DIR}/build --parallel $(nproc)" \
  --overwrite \
  --source-root="${ROOT_DIR}/src/doom-3-bfg"

echo "[CodeQL] Installing query dependencies..."
codeql pack install "${QUERIES_DIR}/../"

echo "[CodeQL] Running queries..."
codeql database analyze "${DB_DIR}" \
  "${QUERIES_DIR}/buffer_access.ql" \
  "${QUERIES_DIR}/uninitialized_var.ql" \
  "${QUERIES_DIR}/integer_overflow.ql" \
  "${QUERIES_DIR}/path_conditions.ql" \
  --format=sarif-latest \
  --output="${SARIF_OUT}"

echo "[CodeQL] Generating Markdown summary..."
python3 - <<'PYEOF'
import json, sys, pathlib, collections, datetime

sarif_path = "${SARIF_OUT}"
summary_path = "${SUMMARY_OUT}"

with open(sarif_path) as f:
    sarif = json.load(f)

rows = []
for run in sarif.get("runs", []):
    rules = {r["id"]: r for r in run.get("tool", {}).get("driver", {}).get("rules", [])}
    for result in run.get("results", []):
        rule_id = result.get("ruleId", "unknown")
        rule = rules.get(rule_id, {})
        name = rule.get("name", rule_id)
        msg  = result.get("message", {}).get("text", "")
        locs = result.get("locations", [])
        loc_str = ""
        if locs:
            pl = locs[0].get("physicalLocation", {})
            uri  = pl.get("artifactLocation", {}).get("uri", "")
            line = pl.get("region", {}).get("startLine", "?")
            loc_str = f"{uri}:{line}"
        rows.append((rule_id, name, loc_str, msg[:120]))

counts = collections.Counter(r[0] for r in rows)

lines = [
    "# CodeQL Analysis Summary",
    f"",
    f"**Generated:** {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}",
    f"**Total findings:** {len(rows)}",
    "",
    "## Finding Counts by Rule",
    "",
    "| Rule ID | Rule Name | Count |",
    "|---------|-----------|------:|",
]
for rid, cnt in sorted(counts.items(), key=lambda x: -x[1]):
    rule_name = next((r[1] for r in rows if r[0] == rid), rid)
    lines.append(f"| `{rid}` | {rule_name} | {cnt} |")

lines += [
    "",
    "## All Findings",
    "",
    "| # | Rule | Location | Message |",
    "|---|------|----------|--------|",
]
for i, (rid, name, loc, msg) in enumerate(rows, 1):
    lines.append(f"| {i} | `{rid}` | `{loc}` | {msg} |")

pathlib.Path(summary_path).write_text("\n".join(lines) + "\n")
print(f"[CodeQL] Wrote {len(rows)} findings to {summary_path}")
PYEOF

echo "[CodeQL] Done. Results in ${REPORTS_DIR}/"
