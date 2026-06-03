#!/usr/bin/env bash
# scripts/run_fuzz.sh
# Orchestrate the full pipeline:
#   1. CodeQL analysis
#   2. OpenGrep scan
#   3. LibFuzzer run for each harness
#   4. Coverage data merge
#   5. Generate final reports

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
BUILD_DIR="${ROOT_DIR}/build"
FUZZERS_DIR="${BUILD_DIR}/fuzzers"
REPORTS_DIR="${ROOT_DIR}/reports"
CORPUS_DIR="${ROOT_DIR}/corpus"

# ── Configurable via env vars ───────────────────────────────────────────────────
FUZZ_TIMEOUT="${FUZZ_TIMEOUT:-60}"     # seconds per harness
FUZZ_MAX_LEN="${FUZZ_MAX_LEN:-4096}"  # max input length in bytes
SKIP_CODEQL="${SKIP_CODEQL:-0}"
SKIP_OPENGREP="${SKIP_OPENGREP:-0}"

mkdir -p "${REPORTS_DIR}" "${CORPUS_DIR}"

echo "===== fuzzing-experiments pipeline ====="
echo "Root:    ${ROOT_DIR}"
echo "Build:   ${BUILD_DIR}"
echo "Reports: ${REPORTS_DIR}"
echo "Timeout: ${FUZZ_TIMEOUT}s per harness"
echo ""

# ── Step 1: CodeQL ──────────────────────────────────────────────────────────────
if [ "${SKIP_CODEQL}" != "1" ]; then
  echo "[Step 1/4] Running CodeQL..."
  bash "${ROOT_DIR}/codeql/run_codeql.sh"
else
  echo "[Step 1/4] CodeQL skipped (SKIP_CODEQL=1)"
fi

# ── Step 2: OpenGrep ────────────────────────────────────────────────────────────
if [ "${SKIP_OPENGREP}" != "1" ]; then
  echo "[Step 2/4] Running OpenGrep..."
  bash "${ROOT_DIR}/opengrep/run_opengrep.sh"
else
  echo "[Step 2/4] OpenGrep skipped (SKIP_OPENGREP=1)"
fi

# ── Step 3: LibFuzzer runs ─────────────────────────────────────────────────────────
echo "[Step 3/4] Running fuzzer harnesses..."

for FUZZER in "${FUZZERS_DIR}"/*; do
  [ -x "${FUZZER}" ] || continue
  NAME=$(basename "${FUZZER}")
  SEED_DIR="${ROOT_DIR}/fuzz/seeds/${NAME#fuzz_}"
  CORPUS_TARGET="${CORPUS_DIR}/${NAME}"
  CRASH_DIR="${REPORTS_DIR}/crashes/${NAME}"

  mkdir -p "${CORPUS_TARGET}" "${CRASH_DIR}"

  # Copy seed corpus if present
  if [ -d "${SEED_DIR}" ]; then
    cp -r "${SEED_DIR}/". "${CORPUS_TARGET}/" 2>/dev/null || true
  fi

  echo "  Running ${NAME} for ${FUZZ_TIMEOUT}s..."
  LLVM_PROFILE_FILE="${REPORTS_DIR}/${NAME}.profraw" \
  "${FUZZER}" \
    "${CORPUS_TARGET}" \
    -max_len="${FUZZ_MAX_LEN}" \
    -max_total_time="${FUZZ_TIMEOUT}" \
    -artifact_prefix="${CRASH_DIR}/" \
    -print_final_stats=1 \
    2>&1 | tee "${REPORTS_DIR}/${NAME}_fuzz.log" || {
      echo "  [!] ${NAME} exited non-zero — check ${CRASH_DIR}/"
    }
done

# ── Step 4: Merge coverage + report ────────────────────────────────────────────────
echo "[Step 4/4] Generating reports..."
bash "${ROOT_DIR}/scripts/generate_report.sh"

echo ""
echo "===== Pipeline complete. Reports in ${REPORTS_DIR}/ ====="
ls -lh "${REPORTS_DIR}"/*.md 2>/dev/null || true
