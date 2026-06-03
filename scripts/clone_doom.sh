#!/usr/bin/env bash
# scripts/clone_doom.sh
# Clone Doom 3 BFG Edition source into src/doom-3-bfg/

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
TARGET_DIR="${ROOT_DIR}/src/doom-3-bfg"

if [ -d "${TARGET_DIR}/.git" ]; then
  echo "[clone_doom] Doom 3 BFG already present at ${TARGET_DIR}. Pulling latest..."
  git -C "${TARGET_DIR}" pull --ff-only
else
  echo "[clone_doom] Cloning id-software/doom-3-bfg into ${TARGET_DIR}..."
  mkdir -p "${ROOT_DIR}/src"
  git clone --depth=1 https://github.com/id-software/doom-3-bfg.git "${TARGET_DIR}"
fi

echo "[clone_doom] Done."
