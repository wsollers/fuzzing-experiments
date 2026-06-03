# fuzz.ps1
# Windows helper script for fuzzing-experiments.
# Requires: Docker Desktop (WSL2 backend), Git for Windows
#
# Run from ANYWHERE — it will clone the repo if needed, or use the existing one.
#
# Usage (from any directory):
#   .\fuzz.ps1
#
# Usage (from inside the repo):
#   .\fuzz.ps1

# ── Step 1: Ensure we are inside the repo root (not a nested copy) ───────────

# Detect if we are already sitting inside fuzzing-experiments
$RepoName = "fuzzing-experiments"
$InRepo   = (Test-Path ".git") -and (
                (Split-Path -Leaf (Get-Location)) -eq $RepoName -or
                (Test-Path (Join-Path (Get-Location) "CMakeLists.txt"))
            )

if ($InRepo) {
    Write-Host "[fuzz.ps1] Already inside repo — pulling latest..."
    git pull
} else {
    # Clone only if the folder doesn't already exist next to this script
    $CloneTarget = Join-Path (Get-Location) $RepoName
    if (Test-Path (Join-Path $CloneTarget ".git")) {
        Write-Host "[fuzz.ps1] Repo folder already exists — pulling latest..."
        git -C $CloneTarget pull --ff-only
    } else {
        Write-Host "[fuzz.ps1] Cloning $RepoName..."
        git clone https://github.com/wsollers/fuzzing-experiments $CloneTarget
    }
    Set-Location $CloneTarget
}

# Safety check: make sure we didn't end up nested inside ourselves
$Cwd = (Get-Location).Path
if ($Cwd -like "*\$RepoName\$RepoName*") {
    Write-Error "ERROR: Detected nested repo path '$Cwd'. Delete the inner '$RepoName' folder and re-run."
    exit 1
}

# ── Step 2: Clone Doom 3 BFG source if not already present ───────────────────
if (-Not (Test-Path "src\doom-3-bfg\.git")) {
    Write-Host "[fuzz.ps1] Cloning Doom 3 BFG source..."
    git clone --depth=1 https://github.com/id-software/doom-3-bfg.git src/doom-3-bfg
} else {
    Write-Host "[fuzz.ps1] Doom 3 BFG source already present, skipping clone."
}

# ── Step 3: Build Docker image ────────────────────────────────────────────────
Write-Host "[fuzz.ps1] Building Docker image..."
docker build -t fuzzing-experiments .

# ── Step 4: Run the full pipeline ─────────────────────────────────────────────
Write-Host "[fuzz.ps1] Running fuzzing pipeline..."
docker run --rm `
  -v ${PWD}/reports:/reports `
  -v ${PWD}/src:/workspace/src `
  fuzzing-experiments
