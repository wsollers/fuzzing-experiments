<#
.SYNOPSIS
    Native Windows build script for fuzzing-experiments.
    Runs from inside a Visual Studio Developer PowerShell or a shell that has
    already sourced a VS environment (e.g. vcvarsall.bat x64).

.DESCRIPTION
    Detects available toolchains in this order:
      1. clang-cl  (LLVM for Windows) — preferred for fuzzing
      2. MSVC cl   (VS 2022 17.0+)   — supports /fsanitize=fuzzer
    Selects the matching CMake preset and builds the project.
    Optionally runs CodeQL and OpenGrep analysis.
    Produces Markdown reports in .\reports\

.PARAMETER Preset
    Override the auto-detected CMake preset name.
    Valid values: windows-msvc-debug, windows-msvc-release, windows-msvc-fuzz,
                  windows-clang-debug, windows-clang-fuzz

.PARAMETER SkipFuzz
    Build only; do not run the fuzzer harnesses.

.PARAMETER SkipCodeQL
    Skip the CodeQL analysis step.

.PARAMETER SkipOpenGrep
    Skip the OpenGrep / Semgrep analysis step.

.PARAMETER FuzzTimeout
    Seconds to run each fuzzer harness (default: 60).

.EXAMPLE
    # Auto-detect toolchain and run everything
    .\build_windows.ps1

.EXAMPLE
    # Force clang-cl fuzz preset, skip analysis tools
    .\build_windows.ps1 -Preset windows-clang-fuzz -SkipCodeQL -SkipOpenGrep

.EXAMPLE
    # Quick build-only check with MSVC
    .\build_windows.ps1 -Preset windows-msvc-release -SkipFuzz -SkipCodeQL -SkipOpenGrep
#>

[CmdletBinding()]
param(
    [string] $Preset      = "",
    [switch] $SkipFuzz,
    [switch] $SkipCodeQL,
    [switch] $SkipOpenGrep,
    [int]    $FuzzTimeout = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────
function Write-Step { param([string]$Msg) Write-Host "`n[build_windows] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  OK  $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  !!  $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "FAIL  $Msg" -ForegroundColor Red; exit 1 }

$RepoRoot   = $PSScriptRoot
$ReportsDir = Join-Path $RepoRoot "reports"
$SrcDir     = Join-Path $RepoRoot "src"
$DoomSrc    = Join-Path $SrcDir   "doom-3-bfg"

New-Item -ItemType Directory -Force $ReportsDir | Out-Null

# ── Step 0: Verify we are in a VS Developer environment ──────────────────────
Write-Step "Checking build environment..."

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Fail "cmake not found. Open a Visual Studio Developer PowerShell or run vcvarsall.bat x64 first."
}
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    Write-Fail "ninja not found. Install via VS Installer (C++ CMake tools) or 'winget install Ninja-build.Ninja'."
}

Write-Ok "cmake $(cmake --version | Select-Object -First 1)"
Write-Ok "ninja $(ninja --version)"

# ── Step 1: Detect toolchain and choose preset ──────────────────────────────
Write-Step "Detecting toolchain..."

$HasClangCL = [bool](Get-Command clang-cl -ErrorAction SilentlyContinue)
$HasCL      = [bool](Get-Command cl       -ErrorAction SilentlyContinue)

if ($Preset -ne "") {
    Write-Ok "Using user-specified preset: $Preset"
} elseif ($HasClangCL) {
    # Check if clang-cl supports -fsanitize=fuzzer by probing the version
    $ClangVersion = (clang-cl --version 2>&1 | Select-String '(\d+)\.' | ForEach-Object {
        [int]($_.Matches[0].Groups[1].Value)
    } | Select-Object -First 1)
    Write-Ok "clang-cl found (major version $ClangVersion)"
    if ($SkipFuzz) {
        $Preset = "windows-clang-debug"
    } else {
        $Preset = "windows-clang-fuzz"
    }
} elseif ($HasCL) {
    # Check MSVC version supports /fsanitize=fuzzer (requires VS 17.0 / cl 19.29+)
    $CLVersion = (cl 2>&1 | Select-String 'Version (\d+)\.').Matches[0].Groups[1].Value
    Write-Ok "MSVC cl found (version prefix $CLVersion)"
    if ([int]$CLVersion -ge 19 -and -not $SkipFuzz) {
        $Preset = "windows-msvc-fuzz"
    } elseif ($SkipFuzz) {
        $Preset = "windows-msvc-release"
    } else {
        Write-Warn "MSVC version may be too old for /fsanitize=fuzzer. Falling back to release build."
        $Preset = "windows-msvc-release"
        $SkipFuzz = $true
    }
} else {
    Write-Fail "No supported compiler found. Install Visual Studio 2022 with C++ workload or LLVM for Windows."
}

Write-Ok "Selected preset: $Preset"
$BuildDir = Join-Path $RepoRoot "build" $Preset

# ── Step 2: Clone Doom 3 BFG if needed ──────────────────────────────────────
Write-Step "Checking Doom 3 BFG source..."

if (-not (Test-Path (Join-Path $DoomSrc ".git"))) {
    Write-Ok "Cloning Doom 3 BFG..."
    git clone --depth=1 https://github.com/id-software/doom-3-bfg.git $DoomSrc
    if ($LASTEXITCODE -ne 0) { Write-Fail "git clone failed." }
} else {
    Write-Ok "Doom 3 BFG source already present."
}

# ── Step 3: CMake configure ────────────────────────────────────────────────────
Write-Step "Configuring with preset '$Preset'..."

push-location $RepoRoot
cmake --preset $Preset
if ($LASTEXITCODE -ne 0) { Write-Fail "CMake configure failed." }
pop-location

Write-Ok "Configure complete. Build dir: $BuildDir"

# ── Step 4: Build ───────────────────────────────────────────────────────────────
Write-Step "Building..."

cmake --build --preset $Preset
if ($LASTEXITCODE -ne 0) { Write-Fail "Build failed. Check output above." }

Write-Ok "Build succeeded."

# ── Step 5: CodeQL ─────────────────────────────────────────────────────────────────
if (-not $SkipCodeQL) {
    Write-Step "Running CodeQL..."

    if (-not (Get-Command codeql -ErrorAction SilentlyContinue)) {
        Write-Warn "codeql not found in PATH. Download from https://github.com/github/codeql-action/releases"
        Write-Warn "Skipping CodeQL step."
    } else {
        $CodeQLDB = Join-Path $BuildDir "codeql_db"
        $SarifOut = Join-Path $ReportsDir "codeql_results.sarif"

        # Build the CodeQL database using the same build command
        codeql database create $CodeQLDB `
            --language=cpp `
            --command="cmake --build --preset $Preset" `
            --overwrite `
            --source-root=(Join-Path $RepoRoot "src\doom-3-bfg")

        if ($LASTEXITCODE -ne 0) { Write-Warn "CodeQL database creation failed; check output." }
        else {
            codeql pack install (Join-Path $RepoRoot "codeql")
            codeql database analyze $CodeQLDB `
                (Join-Path $RepoRoot "codeql\queries\buffer_access.ql") `
                (Join-Path $RepoRoot "codeql\queries\uninitialized_var.ql") `
                (Join-Path $RepoRoot "codeql\queries\integer_overflow.ql") `
                (Join-Path $RepoRoot "codeql\queries\path_conditions.ql") `
                --format=sarif-latest `
                --output=$SarifOut

            Write-Ok "CodeQL results: $SarifOut"
        }
    }
} else {
    Write-Warn "CodeQL skipped (-SkipCodeQL)."
}

# ── Step 6: OpenGrep ──────────────────────────────────────────────────────────────
if (-not $SkipOpenGrep) {
    Write-Step "Running OpenGrep / Semgrep..."

    $GrepCmd = $null
    if (Get-Command opengrep -ErrorAction SilentlyContinue) { $GrepCmd = "opengrep" }
    elseif (Get-Command semgrep -ErrorAction SilentlyContinue) { $GrepCmd = "semgrep" }

    if ($null -eq $GrepCmd) {
        Write-Warn "Neither opengrep nor semgrep found. Install via: pip install opengrep-cli"
        Write-Warn "Skipping OpenGrep step."
    } else {
        $JsonOut = Join-Path $ReportsDir "opengrep_results.json"
        & $GrepCmd `
            --config (Join-Path $RepoRoot "opengrep\rules") `
            --json `
            --output $JsonOut `
            --no-git-ignore `
            (Join-Path $DoomSrc "neo")
        # non-zero exit is normal when findings present
        Write-Ok "OpenGrep results: $JsonOut"
    }
} else {
    Write-Warn "OpenGrep skipped (-SkipOpenGrep)."
}

# ── Step 7: Run fuzzer harnesses ───────────────────────────────────────────────────
if (-not $SkipFuzz) {
    Write-Step "Running fuzzer harnesses (${FuzzTimeout}s each)..."

    $FuzzersDir = Join-Path $BuildDir "fuzzers"
    if (-not (Test-Path $FuzzersDir)) {
        Write-Warn "No fuzzers directory found at $FuzzersDir. Was ENABLE_FUZZING=ON?"
    } else {
        $CrashBase  = Join-Path $ReportsDir "crashes"
        $CorpusBase = Join-Path $RepoRoot   "corpus"
        New-Item -ItemType Directory -Force $CorpusBase | Out-Null

        Get-ChildItem $FuzzersDir -Filter "*.exe" | ForEach-Object {
            $FuzzerExe  = $_.FullName
            $FuzzerName = $_.BaseName
            $SeedDir    = Join-Path $RepoRoot "fuzz\seeds\$($FuzzerName -replace '^fuzz_','')"
            $CorpusDir  = Join-Path $CorpusBase $FuzzerName
            $CrashDir   = Join-Path $CrashBase  $FuzzerName
            $LogFile    = Join-Path $ReportsDir "${FuzzerName}_fuzz.log"

            New-Item -ItemType Directory -Force $CorpusDir | Out-Null
            New-Item -ItemType Directory -Force $CrashDir  | Out-Null

            if (Test-Path $SeedDir) {
                Copy-Item "$SeedDir\*" $CorpusDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            Write-Ok "Running $FuzzerName for ${FuzzTimeout}s..."

            $env:LLVM_PROFILE_FILE = Join-Path $ReportsDir "${FuzzerName}.profraw"

            & $FuzzerExe $CorpusDir `
                "-max_total_time=$FuzzTimeout" `
                "-artifact_prefix=$CrashDir\" `
                "-print_final_stats=1" `
                2>&1 | Tee-Object -FilePath $LogFile

            # Non-zero exit is normal when crashes found
            Write-Ok "$FuzzerName complete. Log: $LogFile"
        }
    }
} else {
    Write-Warn "Fuzzing skipped (-SkipFuzz)."
}

# ── Step 8: Generate Markdown reports ──────────────────────────────────────────────
Write-Step "Generating Markdown reports..."

if (Get-Command python -ErrorAction SilentlyContinue) {
    python (Join-Path $RepoRoot "scripts\generate_report.py") `
        --reports-dir $ReportsDir `
        --build-dir   $BuildDir
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Reports written to $ReportsDir"
    } else {
        Write-Warn "Report generation encountered errors; partial output may exist."
    }
} else {
    Write-Warn "Python not found; skipping report generation."
    Write-Warn "Install Python 3 and re-run, or view raw JSON results in $ReportsDir"
}

# ── Done ────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "===== build_windows.ps1 complete =====" -ForegroundColor Green
Write-Host "  Preset  : $Preset"
Write-Host "  Build   : $BuildDir"
Write-Host "  Reports : $ReportsDir"

$MdFiles = Get-ChildItem $ReportsDir -Filter "*.md" -ErrorAction SilentlyContinue
if ($MdFiles) {
    Write-Host ""
    Write-Host "  Report files:"
    $MdFiles | ForEach-Object { Write-Host "    $($_.Name)" }
}
