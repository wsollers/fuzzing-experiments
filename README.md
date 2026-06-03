# fuzzing-experiments

AST-guided fuzz testing for C/C++ using LibFuzzer, CodeQL, and OpenGrep security analysis — targeting Doom 3 BFG Edition source code.

## What This Does

1. **Clones** Doom 3 BFG source into `src/doom-3-bfg/`
2. **Builds** the code inside a Linux Docker container using Clang + CMake + Ninja with fuzzer/sanitizer instrumentation
3. **Runs CodeQL** to extract AST-level insights: buffer accesses, integer overflows, uninitialized variables, and path/condition coverage hints
4. **Runs OpenGrep** security rules to flag C/C++ memory and integer safety issues
5. **Runs LibFuzzer** harnesses seeded by CodeQL/OpenGrep findings
6. **Generates Markdown reports** covering: path & condition coverage, crash findings, sanitizer hits, CodeQL results, and OpenGrep results

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/wsollers/fuzzing-experiments
cd fuzzing-experiments

# 2. Pull Doom 3 BFG source
./scripts/clone_doom.sh

# 3. Build image and run everything
docker build -t fuzzing-experiments .
docker run --rm \
  -v $(pwd)/reports:/reports \
  -v $(pwd)/src:/src \
  fuzzing-experiments

# 4. View results
cat reports/coverage_report.md
cat reports/findings_report.md
```

## Reports

After a run, `reports/` contains:

| File | Description |
|---|---|
| `coverage_report.md` | Path & condition coverage per fuzzer target |
| `findings_report.md` | Crashes, hangs, and sanitizer findings |
| `codeql_summary.md` | CodeQL AST query results with source locations |
| `opengrep_summary.md` | OpenGrep security scan findings |
| `coverage/index.html` | Full LLVM HTML coverage report |

## Repository Layout

```
.
├── Dockerfile                        # Linux + Clang + CMake + Ninja + CodeQL + OpenGrep
├── CMakeLists.txt                    # Top-level build
├── cmake/
│   ├── clang_fuzzing.cmake           # LibFuzzer + sanitizer compile flags
│   └── sanitizers.cmake              # ASan / UBSan / MSan configuration
├── fuzz/
│   ├── CMakeLists.txt                # Fuzzer target registration
│   ├── harness_template.cpp          # Copy this to create new harnesses
│   ├── doom_idlib_harness.cpp        # idLib string/math fuzzer
│   ├── doom_parser_harness.cpp       # Config/script parser fuzzer
│   └── seeds/                        # Seed corpora
├── codeql/
│   ├── run_codeql.sh                 # Build DB + run all queries
│   ├── qlpack.yml                    # CodeQL pack definition
│   └── queries/
│       ├── buffer_access.ql          # Out-of-bounds buffer access
│       ├── uninitialized_var.ql      # Uninitialized variable reads
│       ├── integer_overflow.ql       # Integer overflow / wraparound
│       └── path_conditions.ql        # Path & condition coverage hints
├── opengrep/
│   ├── run_opengrep.sh               # Run OpenGrep and emit JSON + Markdown
│   └── rules/
│       ├── c_memory_safety.yaml      # strcpy, sprintf, gets, etc.
│       ├── cpp_use_after_free.yaml   # delete then use patterns
│       └── integer_issues.yaml       # Signed overflow, truncation
├── scripts/
│   ├── run_fuzz.sh                   # Orchestrate full fuzzing run
│   ├── generate_report.sh            # Aggregate all results → Markdown
│   └── clone_doom.sh                 # git clone Doom 3 BFG
├── reports/                          # Generated outputs (gitignored except .gitkeep)
│   └── .gitkeep
└── src/
    └── doom-3-bfg/                   # Populated by clone_doom.sh
```

## Adding New Fuzzer Targets

1. Copy `fuzz/harness_template.cpp` to `fuzz/my_target_harness.cpp`
2. Implement the `LLVMFuzzerTestOneInput` function
3. Register in `fuzz/CMakeLists.txt` with `add_fuzzer_target(my_target)`
4. Add seed inputs to `fuzz/seeds/my_target/`

## Toolchain Versions (pinned in Dockerfile)

- Clang 17
- CMake 3.27
- Ninja 1.11
- CodeQL CLI 2.16
- OpenGrep (Semgrep-compatible) latest
- LLVM tools (`llvm-cov`, `llvm-profdata`)
