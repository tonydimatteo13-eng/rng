#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PATH="$PROJECT_DIR/.venv"
AUTOSTART_DIR="${HOME}/.config/autostart"
DESKTOP_FILE="$PROJECT_DIR/system/pi-rng-kiosk.desktop"
SERVICE_FILE="$PROJECT_DIR/system/pi-rng-kiosk.service"

echo "[pi-rng-kiosk] Installing dependencies..."
if [[ ! -d "$VENV_PATH" ]]; then
  python3 -m venv "$VENV_PATH"
fi
# shellcheck disable=SC1090
source "$VENV_PATH/bin/activate"
pip install --upgrade pip
pip install -r "$PROJECT_DIR/requirements.txt"

mkdir -p "$AUTOSTART_DIR"
cp "$DESKTOP_FILE" "$AUTOSTART_DIR/"
sed -i "s|__PROJECT_DIR__|$PROJECT_DIR|g" "$AUTOSTART_DIR/pi-rng-kiosk.desktop"

SYSTEMD_DIR="${HOME}/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"
cp "$SERVICE_FILE" "$SYSTEMD_DIR/"
sed -i "s|__PROJECT_DIR__|$PROJECT_DIR|g" "$SYSTEMD_DIR/pi-rng-kiosk.service"
systemctl --user daemon-reload

echo "[pi-rng-kiosk] Enable autostart via systemd? (y/N)"
read -r ENABLE_SERVICE
if [[ "${ENABLE_SERVICE,,}" == "y" ]]; then
  systemctl --user enable --now pi-rng-kiosk.service
fi

echo "[pi-rng-kiosk] Disabling screen blanking for current session"
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.session idle-delay 0 || true
fi
if command -v xset >/dev/null 2>&1; then
  xset s off || true
  xset -dpms || true
fi

echo "[pi-rng-kiosk] Installation complete. Reboot to verify autostart."

