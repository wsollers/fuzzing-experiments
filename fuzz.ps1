# fuzz.ps1
# Windows helper script for fuzzing-experiments.
# Requires: Docker Desktop (WSL2 backend), Git for Windows
#
# Usage (first time):
#   .\fuzz.ps1
#
# Usage (subsequent runs from inside the repo folder):
#   git pull; .\fuzz.ps1

# ── Step 1: Clone the repo if we're not already inside it ────────────────────
if (-Not (Test-Path ".git")) {
    git clone https://github.com/wsollers/fuzzing-experiments
    Set-Location fuzzing-experiments
} else {
    Write-Host "[fuzz.ps1] Already inside repo — pulling latest..."
    git pull
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
