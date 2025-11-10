#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

if [[ ! -d .git ]]; then
  echo "[pi-rng-kiosk] No git repository found; skipping update"
  exit 0
fi

echo "[pi-rng-kiosk] Pulling latest main..."
git fetch origin main >/dev/null 2>&1 || true
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "$LOCAL")
if [[ "$LOCAL" == "$REMOTE" ]]; then
  echo "[pi-rng-kiosk] Already on latest main"
  exit 0
fi

git reset --hard origin/main
if [[ -x .venv/bin/pip ]]; then
  .venv/bin/pip install -r requirements.txt >/dev/null 2>&1 || true
fi

echo "[pi-rng-kiosk] Updated to $(git rev-parse --short HEAD)"
