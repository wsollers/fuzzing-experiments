<#
.SYNOPSIS
    Native Windows build script for fuzzing-experiments.
    Can be run from ANY PowerShell window -- no Developer Prompt required.
    Auto-locates Visual Studio via vswhere and sets up the build environment.

.DESCRIPTION
    Detects and initialises the VS build environment automatically, then
    detects available toolchains in this order:
      1. clang-cl  (LLVM for Windows) -- preferred for fuzzing
      2. MSVC cl   (VS 2022 17.0+)   -- supports /fsanitize=fuzzer
    Selects the matching CMake preset and builds the project.
    Optionally runs CodeQL and OpenGrep analysis.
    Produces Markdown reports in .\reports\

.PARAMETER Preset
    Override the auto-detected CMake preset name.
    Valid values: windows-msvc-debug, windows-msvc-release, windows-msvc-fuzz,
                  windows-clang-debug, windows-clang-fuzz

.PARAMETER VSYear
    Prefer a specific VS install year: 2022 or 18 (preview).
    Default: 2022

.PARAMETER SkipFuzz
    Build only; do not run the fuzzer harnesses.

.PARAMETER SkipCodeQL
    Skip the CodeQL analysis step.

.PARAMETER SkipOpenGrep
    Skip the OpenGrep / Semgrep analysis step.

.PARAMETER FuzzTimeout
    Seconds to run each fuzzer harness (default: 60).

.PARAMETER FuzzRssLimitMb
    libFuzzer RSS limit in MB (default: 4096). Use 0 to disable libFuzzer's
    memory limit.

.EXAMPLE
    # Auto-detect everything and run the full pipeline
    .\build_windows.ps1

.EXAMPLE
    # Force clang-cl fuzz preset, skip analysis tools
    .\build_windows.ps1 -Preset windows-clang-fuzz -SkipCodeQL -SkipOpenGrep

.EXAMPLE
    # Quick build-only check with MSVC, no fuzzing
    .\build_windows.ps1 -Preset windows-msvc-release -SkipFuzz -SkipCodeQL -SkipOpenGrep

.EXAMPLE
    # Use the VS 18 preview install instead of 2022
    .\build_windows.ps1 -VSYear 18
#>

[CmdletBinding()]
param(
    [string] $Preset      = "",
    [string] $VSYear      = "2022",
    [switch] $SkipFuzz,
    [switch] $SkipCodeQL,
    [switch] $SkipOpenGrep,
    [int]    $FuzzTimeout = 60,
    [int]    $FuzzRssLimitMb = 4096
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Helpers ------------------------------------------------------------------
function Write-Step { param([string]$Msg) Write-Host "`n[build_windows] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  OK  $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  !!  $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "FAIL  $Msg" -ForegroundColor Red; exit 1 }

function ConvertTo-WindowsCommandLineArgument {
    param([string]$Argument)

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq '\') {
            $backslashes++
            continue
        }
        if ($ch -eq '"') {
            [void]$builder.Append('\' * (($backslashes * 2) + 1))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append('\' * $backslashes)
            $backslashes = 0
        }
        [void]$builder.Append($ch)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append('\' * ($backslashes * 2))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-NativeWithTee {
    param(
        [string] $Exe,
        [string[]] $Arguments,
        [string] $LogFile
    )

    $ArgumentLine = ($Arguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument $_ }) -join " "
    $StdOutFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    $StdErrFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    try {
        $proc = Start-Process -FilePath $Exe `
            -ArgumentList $ArgumentLine `
            -WorkingDirectory $RepoRoot `
            -RedirectStandardOutput $StdOutFile `
            -RedirectStandardError $StdErrFile `
            -NoNewWindow `
            -Wait `
            -PassThru

        $Output = @()
        if (Test-Path $StdOutFile) {
            $Output += Get-Content $StdOutFile
        }
        if (Test-Path $StdErrFile) {
            $Output += Get-Content $StdErrFile
        }
        $Output | Set-Content -Path $LogFile -Encoding UTF8
        foreach ($Line in $Output) {
            Write-Host $Line
        }
        return $proc.ExitCode
    } finally {
        Remove-Item $StdOutFile, $StdErrFile -Force -ErrorAction SilentlyContinue
    }
}

# Safe compiler version probe -- captures output into a variable before use.
function Get-VersionString {
    param([string]$Exe, [string]$Args = "--version")
    try {
        $raw = & $Exe $Args.Split(" ") 2>&1
        return ($raw | Where-Object { $_ -match '\d+\.\d+' } | Select-Object -First 1) -as [string]
    } catch { return "unknown" }
}

$RepoRoot   = $PSScriptRoot
$ReportsDir = Join-Path $RepoRoot "reports"
$SrcDir     = Join-Path $RepoRoot "src"
$DoomSrc    = Join-Path $SrcDir   "doom-3-bfg"

New-Item -ItemType Directory -Force $ReportsDir | Out-Null

# --- Step 0: Locate and initialise the VS build environment -------------------
Write-Step "Locating Visual Studio build environment..."

function Find-VcVarsAll {
    param([string]$Year)

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $installPaths = & $vswhere -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null

        $match = $installPaths |
            Where-Object { $_ -like "*\$Year\*" } |
            Select-Object -First 1

        if (-not $match) {
            $match = $installPaths | Select-Object -First 1
        }

        if ($match) {
            $candidate = Join-Path $match "VC\Auxiliary\Build\vcvarsall.bat"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    $all = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\18\Professional\VC\Auxiliary\Build\vcvarsall.bat",
        "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat"
    )
    $sorted = ($all | Where-Object { $_ -like "*\$Year\*" }) +
              ($all | Where-Object { $_ -notlike "*\$Year\*" })
    return $sorted | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (Get-Command cl -ErrorAction SilentlyContinue) {
    Write-Ok "Build environment already active (cl found in PATH)."
} else {
    $vcvars = Find-VcVarsAll -Year $VSYear
    if (-not $vcvars) {
        Write-Fail "Could not find vcvarsall.bat. Install Visual Studio 2022 with the 'Desktop development with C++' workload."
    }

    Write-Ok "Found: $vcvars"
    Write-Ok "Initialising x64 build environment..."

    $envLines = cmd /c "`"$vcvars`" x64 >nul 2>&1 && set"
    if (-not $envLines) {
        Write-Fail "vcvarsall.bat produced no output. Check your VS installation."
    }

    foreach ($line in $envLines) {
        if ($line -match '^([A-Za-z_][A-Za-z0-9_(){}]*)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
    Write-Ok "VS environment loaded from $vcvars"
}

foreach ($tool in @("cl", "cmake", "ninja")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Fail "'$tool' not found. Ensure 'C++ CMake tools for Windows' is installed in VS Installer."
    }
}

$clVer    = Get-VersionString -Exe "cl" -Args ""
$cmakeVer = (cmake --version 2>&1 | Select-Object -First 1) -as [string]
$ninjaVer = (ninja --version  2>&1 | Select-Object -First 1) -as [string]
Write-Ok "cl    : $clVer"
Write-Ok "cmake : $cmakeVer"
Write-Ok "ninja : $ninjaVer"

# --- Step 1: Detect toolchain and choose preset -------------------------------
Write-Step "Detecting toolchain..."

$HasClangCL = [bool](Get-Command clang-cl -ErrorAction SilentlyContinue)
$HasCL      = [bool](Get-Command cl       -ErrorAction SilentlyContinue)

if ($Preset -ne "") {
    Write-Ok "Using user-specified preset: $Preset"

} elseif ($HasClangCL) {
    $clangVerRaw  = (clang-cl --version 2>&1) -as [string[]]
    $clangVerLine = ($clangVerRaw | Select-Object -First 1) -as [string]
    $clangMajor   = if ($clangVerLine -match '(\d+)\.') { [int]$Matches[1] } else { 0 }
    Write-Ok "clang-cl $clangMajor found: $clangVerLine"
    $Preset = if ($SkipFuzz) { "windows-clang-debug" } else { "windows-clang-fuzz" }

} elseif ($HasCL) {
    $clVerRaw  = (cl 2>&1) -as [string[]]
    $clVerLine = ($clVerRaw | Where-Object { $_ -match 'Version' } | Select-Object -First 1) -as [string]
    $clMajor   = if ($clVerLine -match 'Version (\d+)\.') { [int]$Matches[1] } else { 0 }
    Write-Ok "MSVC cl $clMajor found: $clVerLine"

    if ($SkipFuzz) {
        $Preset = "windows-msvc-release"
    } elseif ($clMajor -ge 19) {
        $Preset = "windows-msvc-fuzz"
    } else {
        Write-Warn "MSVC cl version too old for /fsanitize=fuzzer (need 19.29+). Falling back to release."
        $Preset   = "windows-msvc-release"
        $SkipFuzz = $true
    }

} else {
    Write-Fail "No supported C++ compiler found."
}

Write-Ok "Selected preset: $Preset"
$BuildDir = Join-Path (Join-Path $RepoRoot "build") $Preset

# --- Step 2: Clone Doom 3 BFG if needed ---------------------------------------
Write-Step "Checking Doom 3 BFG source..."

if (-not (Test-Path (Join-Path $DoomSrc ".git"))) {
    Write-Ok "Cloning Doom 3 BFG..."
    git clone --depth=1 https://github.com/id-software/doom-3-bfg.git $DoomSrc
    if ($LASTEXITCODE -ne 0) { Write-Fail "git clone failed." }
} else {
    Write-Ok "Doom 3 BFG source already present."
}

# --- Step 3: CMake configure --------------------------------------------------
Write-Step "Configuring with preset '$Preset'..."

Push-Location $RepoRoot
& cmake --preset "$Preset"
if ($LASTEXITCODE -ne 0) { Write-Fail "CMake configure failed." }
Pop-Location

Write-Ok "Configure complete -- build dir: $BuildDir"

# --- Step 4: Build ------------------------------------------------------------
Write-Step "Building..."

& cmake --build --preset "$Preset"
if ($LASTEXITCODE -ne 0) { Write-Fail "Build failed. Check output above." }

Write-Ok "Build succeeded."

# --- Step 5: CodeQL -----------------------------------------------------------
if (-not $SkipCodeQL) {
    Write-Step "Running CodeQL..."

    if (-not (Get-Command codeql -ErrorAction SilentlyContinue)) {
        Write-Warn "codeql not found. Download from: https://github.com/github/codeql-action/releases"
        Write-Warn "Skipping CodeQL step."
    } else {
        $CodeQLDB = Join-Path $BuildDir "codeql_db"
        $SarifOut = Join-Path $ReportsDir "codeql_results.sarif"

        codeql database create "$CodeQLDB" `
            --language=cpp `
            --command="cmake --build --preset $Preset" `
            --overwrite `
            --source-root="$RepoRoot\src\doom-3-bfg"

        if ($LASTEXITCODE -ne 0) {
            Write-Warn "CodeQL database creation failed."
        } else {
            codeql pack install "$RepoRoot\codeql"
            codeql database analyze "$CodeQLDB" `
                "$RepoRoot\codeql\queries\buffer_access.ql" `
                "$RepoRoot\codeql\queries\uninitialized_var.ql" `
                "$RepoRoot\codeql\queries\integer_overflow.ql" `
                "$RepoRoot\codeql\queries\path_conditions.ql" `
                --format=sarif-latest `
                --output="$SarifOut"
            Write-Ok "CodeQL results: $SarifOut"
        }
    }
} else {
    Write-Warn "CodeQL skipped (-SkipCodeQL)."
}

# --- Step 6: OpenGrep ---------------------------------------------------------
if (-not $SkipOpenGrep) {
    Write-Step "Running OpenGrep / Semgrep..."

    $GrepCmd = $null
    if     (Get-Command opengrep -ErrorAction SilentlyContinue) { $GrepCmd = "opengrep" }
    elseif (Get-Command semgrep  -ErrorAction SilentlyContinue) { $GrepCmd = "semgrep"  }

    if ($null -eq $GrepCmd) {
        Write-Warn "Neither opengrep nor semgrep found. Install via: pip install opengrep-cli"
        Write-Warn "Skipping OpenGrep step."
    } else {
        $JsonOut = Join-Path $ReportsDir "opengrep_results.json"
        & $GrepCmd `
            --config "$RepoRoot\opengrep\rules" `
            --json --output "$JsonOut" `
            --no-git-ignore `
            "$DoomSrc\neo"
        Write-Ok "OpenGrep results: $JsonOut"
    }
} else {
    Write-Warn "OpenGrep skipped (-SkipOpenGrep)."
}

# --- Step 7: Run fuzzer harnesses ---------------------------------------------
if (-not $SkipFuzz) {
    Write-Step "Running fuzzer harnesses (${FuzzTimeout}s each)..."

    $FuzzersDir = Join-Path $BuildDir "fuzzers"
    if (-not (Test-Path $FuzzersDir)) {
        Write-Warn "No fuzzers directory at $FuzzersDir -- was ENABLE_FUZZING=ON?"
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

            $FuzzerArgs = @(
                $CorpusDir,
                "-max_total_time=$FuzzTimeout",
                "-rss_limit_mb=$FuzzRssLimitMb",
                "-artifact_prefix=$CrashDir\",
                "-print_final_stats=1"
            )

            $ExitCode = Invoke-NativeWithTee -Exe $FuzzerExe -Arguments $FuzzerArgs -LogFile $LogFile

            if ($ExitCode -ne 0) {
                Write-Fail "$FuzzerName failed with exit code $ExitCode. Log: $LogFile"
            }

            Write-Ok "$FuzzerName complete -- log: $LogFile"
        }
    }
} else {
    Write-Warn "Fuzzing skipped (-SkipFuzz)."
}

# --- Step 8: Generate Markdown reports ----------------------------------------
Write-Step "Generating Markdown reports..."

if (Get-Command python -ErrorAction SilentlyContinue) {
    python "$RepoRoot\scripts\generate_report.py" `
        --reports-dir "$ReportsDir" `
        --build-dir   "$BuildDir"
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Reports written to $ReportsDir"
    } else {
        Write-Warn "Report generation had errors -- partial output may exist."
    }
} else {
    Write-Warn "Python not found -- skipping report generation."
    Write-Warn "Install Python 3 and re-run, or view raw JSON in $ReportsDir"
}

# --- Done ---------------------------------------------------------------------
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
