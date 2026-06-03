#!/usr/bin/env python3
"""
scripts/generate_report.py
Cross-platform Python replacement for generate_report.sh.
Merges LLVM coverage data (if available) and produces:
  reports/coverage_report.md
  reports/findings_report.md
  reports/codeql_summary.md   (if codeql_results.sarif exists)
  reports/opengrep_summary.md (if opengrep_results.json exists)

Usage:
  python scripts/generate_report.py --reports-dir ./reports --build-dir ./build/windows-msvc-fuzz
"""

import argparse
import collections
import datetime
import json
import pathlib
import re
import shutil
import subprocess
import sys


def now() -> str:
    return datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")


# ───────────────────────────────────────────────────────────────────────────────
def generate_coverage_report(reports: pathlib.Path, build: pathlib.Path) -> None:
    lcov = reports / "coverage.lcov"
    lines = [
        "# Coverage Report",
        "",
        f"**Generated:** {now()}",
        f"**Preset / build:** `{build.name}`",
        "",
    ]

    # Try to merge profraw → profdata → lcov using llvm tools
    profraws = list(reports.glob("*.profraw"))
    if profraws and shutil.which("llvm-profdata"):
        profdata = reports / "merged.profdata"
        cmd = ["llvm-profdata", "merge", "-sparse"] + [str(p) for p in profraws] + ["-o", str(profdata)]
        result = subprocess.run(cmd, capture_output=True)
        if result.returncode == 0 and shutil.which("llvm-cov"):
            fuzzers_dir = build / "fuzzers"
            exes = list(fuzzers_dir.glob("*.exe")) + list(fuzzers_dir.glob("fuzz_*"))
            if exes:
                lcov_cmd = ["llvm-cov", "export",
                            f"-instr-profile={profdata}",
                            str(exes[0])]
                for e in exes[1:]:
                    lcov_cmd += ["-object", str(e)]
                lcov_cmd += ["-format=lcov"]
                with open(lcov, "w") as f:
                    subprocess.run(lcov_cmd, stdout=f)

    if lcov.exists():
        file_stats: dict = {}
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
        lp = (total_lh / total_lt * 100) if total_lt else 0
        bp = (total_bh / total_bt * 100) if total_bt else 0

        lines += [
            "## Overall Coverage", "",
            "| Metric | Hit | Total | % |",
            "|--------|----:|------:|--:|",
            f"| Line (path proxy) | {total_lh} | {total_lt} | {lp:.1f}% |",
            f"| Branch (condition) | {total_bh} | {total_bt} | {bp:.1f}% |",
            "",
            "## Per-File Coverage", "",
            "| File | Line % | Branch % |",
            "|------|-------:|---------:|",
        ]
        for fname, s in sorted(file_stats.items()):
            short = pathlib.Path(fname).name
            lp2 = (s["lh"] / s["lt"] * 100) if s["lt"] else 0
            bp2 = (s["bh"] / s["bt"] * 100) if s["bt"] else 0
            lines.append(f"| `{short}` | {lp2:.1f}% | {bp2:.1f}% |")
    else:
        lines += [
            "> No LLVM coverage data found.",
            "> Run the fuzzer first, or ensure `llvm-profdata` and `llvm-cov` are in PATH.",
        ]

    lines += [
        "",
        "## Coverage Guidance from CodeQL",
        "",
        "See `codeql_summary.md` for branch conditions identified by `path_conditions.ql`.",
        "Each listed location is a branch that can be flipped by adding a targeted seed.",
    ]

    (reports / "coverage_report.md").write_text("\n".join(lines) + "\n")
    print("[report] Wrote coverage_report.md")


# ───────────────────────────────────────────────────────────────────────────────
def generate_findings_report(reports: pathlib.Path) -> None:
    crash_dir = reports / "crashes"
    crash_files = list(crash_dir.glob("**/*")) if crash_dir.exists() else []
    crash_files = [f for f in crash_files if f.is_file()]

    lines = [
        "# Fuzzer Findings Report", "",
        f"**Generated:** {now()}", "",
        "## Summary", "",
        "| Metric | Value |",
        "|--------|-------|",
        f"| Total crash/hang artifacts | {len(crash_files)} |",
    ]

    log_stats = []
    for log_file in sorted(reports.glob("*_fuzz.log")):
        name = log_file.stem.replace("_fuzz", "")
        text = log_file.read_text(errors="replace")
        execs = re.search(r"stat::number_of_executed_units:\s*(\d+)", text)
        eps   = re.search(r"stat::average_exec_per_sec:\s*([\d.]+)", text)
        feat  = re.search(r"stat::new_units_added:\s*(\d+)", text)
        log_stats.append({
            "name":   name,
            "execs":  execs.group(1) if execs else "?",
            "eps":    eps.group(1)   if eps   else "?",
            "corpus": feat.group(1)  if feat  else "?",
        })

    if log_stats:
        lines += [
            "", "## Fuzzer Run Statistics", "",
            "| Harness | Executions | Exec/sec | New corpus units |",
            "|---------|----------:|--------:|-----------------:|",
        ]
        for s in log_stats:
            lines.append(f"| `{s['name']}` | {s['execs']} | {s['eps']} | {s['corpus']} |")

    if crash_files:
        lines += [
            "", "## Crash / Hang Artifacts", "",
            "| Harness | Artifact | Size |",
            "|---------|----------|-----:|",
        ]
        for cf in sorted(crash_files):
            lines.append(f"| `{cf.parent.name}` | `{cf.name}` | {cf.stat().st_size} B |")
        lines += [
            "",
            "> **Reproducing:** `./build/fuzzers/<harness>[.exe] reports/crashes/<harness>/<artifact>`",
        ]
    else:
        lines += ["", "No crash artifacts found in this run."]

    asan = [lf.stem for lf in reports.glob("*_fuzz.log")
            if "AddressSanitizer" in lf.read_text(errors="replace")
            or "UndefinedBehaviorSanitizer" in lf.read_text(errors="replace")]
    if asan:
        lines += ["", "## Sanitizer Hits", ""] + [f"- `{h}`" for h in asan]

    (reports / "findings_report.md").write_text("\n".join(lines) + "\n")
    print("[report] Wrote findings_report.md")


# ───────────────────────────────────────────────────────────────────────────────
def generate_codeql_summary(reports: pathlib.Path) -> None:
    sarif_path = reports / "codeql_results.sarif"
    if not sarif_path.exists():
        return

    with open(sarif_path) as f:
        sarif = json.load(f)

    rows = []
    for run in sarif.get("runs", []):
        rules = {r["id"]: r for r in run.get("tool", {}).get("driver", {}).get("rules", [])}
        for result in run.get("results", []):
            rule_id = result.get("ruleId", "unknown")
            rule    = rules.get(rule_id, {})
            name    = rule.get("name", rule_id)
            msg     = result.get("message", {}).get("text", "")
            locs    = result.get("locations", [])
            loc_str = ""
            if locs:
                pl      = locs[0].get("physicalLocation", {})
                uri     = pl.get("artifactLocation", {}).get("uri", "")
                line    = pl.get("region", {}).get("startLine", "?")
                loc_str = f"{pathlib.Path(uri).name}:{line}"
            rows.append((rule_id, name, loc_str, msg[:120]))

    counts = collections.Counter(r[0] for r in rows)
    lines = [
        "# CodeQL Analysis Summary", "",
        f"**Generated:** {now()}",
        f"**Total findings:** {len(rows)}",
        "", "## Finding Counts by Rule", "",
        "| Rule ID | Rule Name | Count |",
        "|---------|-----------|------:|",
    ]
    for rid, cnt in sorted(counts.items(), key=lambda x: -x[1]):
        rname = next((r[1] for r in rows if r[0] == rid), rid)
        lines.append(f"| `{rid}` | {rname} | {cnt} |")

    lines += ["", "## All Findings", "",
              "| # | Rule | Location | Message |",
              "|---|------|----------|--------|"
    ]
    for i, (rid, name, loc, msg) in enumerate(rows, 1):
        lines.append(f"| {i} | `{rid}` | `{loc}` | {msg} |")

    (reports / "codeql_summary.md").write_text("\n".join(lines) + "\n")
    print("[report] Wrote codeql_summary.md")


# ───────────────────────────────────────────────────────────────────────────────
def generate_opengrep_summary(reports: pathlib.Path) -> None:
    json_path = reports / "opengrep_results.json"
    if not json_path.exists():
        return

    with open(json_path) as f:
        data = json.load(f)

    results = data.get("results", [])
    counts  = collections.Counter(r["check_id"] for r in results)
    sev_map = {r["check_id"]: r.get("extra", {}).get("severity", "?") for r in results}

    lines = [
        "# OpenGrep Security Scan Summary", "",
        f"**Generated:** {now()}",
        f"**Total findings:** {len(results)}",
        "", "## Findings by Rule", "",
        "| Rule ID | Severity | Count |",
        "|---------|----------|------:|",
    ]
    for rid, cnt in sorted(counts.items(), key=lambda x: -x[1]):
        lines.append(f"| `{rid}` | {sev_map.get(rid, '?')} | {cnt} |")

    lines += ["", "## All Findings", "",
              "| # | Rule | File | Line | Message |",
              "|---|------|------|-----:|---------|"
    ]
    for i, r in enumerate(results, 1):
        rule  = r.get("check_id", "")
        path  = pathlib.Path(r.get("path", "")).name
        start = r.get("start", {}).get("line", "?")
        msg   = r.get("extra", {}).get("message", "")[:100].replace("\n", " ")
        lines.append(f"| {i} | `{rule}` | `{path}` | {start} | {msg} |")

    (reports / "opengrep_summary.md").write_text("\n".join(lines) + "\n")
    print("[report] Wrote opengrep_summary.md")


# ───────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate fuzzing reports")
    parser.add_argument("--reports-dir", required=True)
    parser.add_argument("--build-dir",   required=True)
    args = parser.parse_args()

    reports = pathlib.Path(args.reports_dir)
    build   = pathlib.Path(args.build_dir)
    reports.mkdir(parents=True, exist_ok=True)

    generate_coverage_report(reports, build)
    generate_findings_report(reports)
    generate_codeql_summary(reports)
    generate_opengrep_summary(reports)

    print("[report] All reports complete.")
