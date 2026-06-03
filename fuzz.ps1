# fuzz.ps1
# Windows helper script for fuzzing-experiments.
# Requires: Docker Desktop (WSL2 backend), Git for Windows
#
# Usage:
#   .\fuzz.ps1

# Install Docker Desktop, then:
git clone https://github.com/wsollers/fuzzing-experiments
cd fuzzing-experiments

# Clone Doom source (Git for Windows or WSL)
git clone --depth=1 https://github.com/id-software/doom-3-bfg.git src/doom-3-bfg

# Build and run — identical to Linux/Mac
docker build -t fuzzing-experiments .
docker run --rm `
  -v ${PWD}/reports:/reports `
  -v ${PWD}/src:/workspace/src `
  fuzzing-experiments
