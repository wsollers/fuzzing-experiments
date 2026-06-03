#!/usr/bin/env bash
# scripts/generate_report.sh
# Merge LLVM profraw files, generate coverage data, and produce:
#   reports/coverage_report.md  — path & condition coverage
#   reports/findings_report.md  — crashes and sanitizer hits
#   reports/coverage/           — HTML coverage report

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
BUILD_DIR="${ROOT_DIR}/build"
FUZZERS_DIR="${BUILD_DIR}/fuzzers"
REPORTS_DIR="${ROOT_DIR}/reports"
COV_DIR="${REPORTS_DIR}/coverage"

mkdir -p "${COV_DIR}"

# ── Merge profraw files ─────────────────────────────────────────────────────────
PROFRAW_FILES=("${REPORTS_DIR}"/*.profraw)
if [ "${#PROFRAW_FILES[@]}" -eq 0 ] || [ ! -f "${PROFRAW_FILES[0]}" ]; then
  echo "[Coverage] No .profraw files found — skipping LLVM coverage."
else
  echo "[Coverage] Merging ${#PROFRAW_FILES[@]} profile(s)..."
  llvm-profdata merge -sparse "${PROFRAW_FILES[@]}" \
    -o "${REPORTS_DIR}/merged.profdata"

  # Collect fuzzer binaries for coverage report
  FUZZER_BINS=()
  for F in "${FUZZERS_DIR}"/*; do
    [ -x "${F}" ] && FUZZER_BINS+=("${F}")
  done

  if [ "${#FUZZER_BINS[@]}" -gt 0 ]; then
    # HTML report
    llvm-cov show \
      -instr-profile="${REPORTS_DIR}/merged.profdata" \
      "${FUZZER_BINS[0]}" \
      "${FUZZER_BINS[@]:1/#/-object }" \
      -format=html \
      -output-dir="${COV_DIR}" \
      -show-branches=count \
      -show-line-counts-or-regions

    # Per-file coverage JSON for Markdown processing
    llvm-cov export \
      -instr-profile="${REPORTS_DIR}/merged.profdata" \
      "${FUZZER_BINS[0]}" \
      "${FUZZER_BINS[@]:1/#/-object }" \
      -format=lcov \
      > "${REPORTS_DIR}/coverage.lcov"

    echo "[Coverage] HTML report: ${COV_DIR}/index.html"
  fi
fi

# ── Generate coverage_report.md (path & condition coverage) ──────────────────
python3 - <<'PYEOF'
import pathlib, re, datetime, os

reports = pathlib.Path("${REPORTS_DIR}")
lcov    = reports / "coverage.lcov"

lines = [
    "# Coverage Report",
    "",
    f"**Generated:** {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}",
    "",
]

if lcov.exists():
    # Parse LCOV: DA lines = line hits, BRDA lines = branch hits
    file_stats = {}  # file -> {lines_hit, lines_total, branches_hit, branches_total}
    cur = None
    for raw in lcov.read_text().splitlines():
        if raw.startswith("SF:"):
            cur = raw[3:]
            file_stats.setdefault(cur, dict(lh=0, lt=0, bh=0, bt=0))
        elif raw.startswith("DA:") and cur:
            _, hits = raw[3:].split(",")[:2]
            file_stats[cur]["lt"] += 1
            if int(hits) > 0:
                file_stats[cur]["lh"] += 1
        elif raw.startswith("BRDA:") and cur:
            parts = raw[5:].split(",")
            if len(parts) >= 4:
                file_stats[cur]["bt"] += 1
                if parts[3] not in ("-", "0"):
                    file_stats[cur]["bh"] += 1

    total_lh = sum(v["lh"] for v in file_stats.values())
    total_lt = sum(v["lt"] for v in file_stats.values())
    total_bh = sum(v["bh"] for v in file_stats.values())
    total_bt = sum(v["bt"] for v in file_stats.values())
    line_pct   = (total_lh / total_lt * 100)   if total_lt else 0
    branch_pct = (total_bh / total_bt * 100)   if total_bt else 0

    lines += [
        "## Overall Coverage",
        "",
        f"| Metric | Hit | Total | % |",
        f"|--------|----:|------:|--:|",
        f"| Line (path proxy) | {total_lh} | {total_lt} | {line_pct:.1f}% |",
        f"| Branch (condition) | {total_bh} | {total_bt} | {branch_pct:.1f}% |",
        "",
        "## Per-File Coverage",
        "",
        "| File | Line % | Branch % |",
        "|------|-------:|---------:|",
    ]

    for fname, s in sorted(file_stats.items(), key=lambda x: x[0]):
        short = fname.replace(str(reports.parent), "")
        lp = (s["lh"]/s["lt"]*100) if s["lt"] else 0
        bp = (s["bh"]/s["bt"]*100) if s["bt"] else 0
        lines.append(f"| `{short}` | {lp:.1f}% | {bp:.1f}% |")
else:
    lines += [
        "> No LCOV data found. Run the fuzzer first to generate coverage.",
        "",
        "Coverage will appear here after `scripts/run_fuzz.sh` completes.",
    ]

lines += [
    "",
    "## Coverage Guidance from CodeQL",
    "",
    "See `codeql_summary.md` for branch conditions identified by the",
    "`path_conditions.ql` query. Each listed location is a branch that",
    "requires a specific input pattern to exercise — add matching inputs",
    "to the relevant seed corpus directory to improve branch coverage.",
]

(reports / "coverage_report.md").write_text("\n".join(lines) + "\n")
print("[Report] Wrote coverage_report.md")
PYEOF

# ── Generate findings_report.md ─────────────────────────────────────────────────────
python3 - <<'PYEOF'
import pathlib, re, datetime, glob

reports   = pathlib.Path("${REPORTS_DIR}")
crash_dir = reports / "crashes"

lines = [
    "# Fuzzer Findings Report",
    "",
    f"**Generated:** {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}",
    "",
]

all_crashes = list(crash_dir.glob("**/*")) if crash_dir.exists() else []
crash_files = [f for f in all_crashes if f.is_file()]

lines += [
    f"## Summary",
    "",
    f"| Metric | Value |",
    f"|--------|-------|",
    f"| Total crash/hang artifacts | {len(crash_files)} |",
]

# Parse fuzzer log stats
log_stats = []
for log_file in sorted(reports.glob("*_fuzz.log")):
    name = log_file.stem.replace("_fuzz", "")
    text = log_file.read_text()
    execs = re.search(r"stat::number_of_executed_units:\s*(\d+)", text)
    cov   = re.search(r"stat::average_exec_per_sec:\s*([\d.]+)", text)
    feat  = re.search(r"stat::new_units_added:\s*(\d+)", text)
    log_stats.append({
        "name": name,
        "execs":  execs.group(1) if execs else "?",
        "eps":    cov.group(1)   if cov   else "?",
        "corpus": feat.group(1)  if feat  else "?",
    })

if log_stats:
    lines += [
        "",
        "## Fuzzer Run Statistics",
        "",
        "| Harness | Executions | Exec/sec | New corpus units |",
        "|---------|----------:|--------:|-----------------:|",
    ]
    for s in log_stats:
        lines.append(f"| `{s['name']}` | {s['execs']} | {s['eps']} | {s['corpus']} |")

if crash_files:
    lines += [
        "",
        "## Crash / Hang Artifacts",
        "",
        "| Harness | Artifact | Size |",
        "|---------|----------|-----:|",
    ]
    for cf in sorted(crash_files):
        harness = cf.parent.name
        size    = cf.stat().st_size
        lines.append(f"| `{harness}` | `{cf.name}` | {size} B |")
    lines += [
        "",
        "> **Reproducing a crash:**",
        "> ```bash",
        "> ./build/fuzzers/<harness> reports/crashes/<harness>/<artifact>",
        "> ```",
    ]
else:
    lines += [
        "",
        "No crash artifacts found in this run. ",
        "Crashes will appear here when the fuzzer finds an input that causes a fault.",
    ]

# Sanitizer summary from logs
asan_hits = []
for log_file in sorted(reports.glob("*_fuzz.log")):
    text = log_file.read_text()
    if "AddressSanitizer" in text or "UndefinedBehaviorSanitizer" in text:
        asan_hits.append(log_file.stem)

if asan_hits:
    lines += [
        "",
        "## Sanitizer Hits",
        "",
        "The following harnesses triggered sanitizer reports (ASan/UBSan):",
        "",
    ] + [f"- `{h}`" for h in asan_hits]

(reports / "findings_report.md").write_text("\n".join(lines) + "\n")
print("[Report] Wrote findings_report.md")
PYEOF

echo "[Report] All reports generated in ${REPORTS_DIR}/"
