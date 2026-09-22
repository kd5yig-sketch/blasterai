#!/usr/bin/env bash
# Installs Blaster as a kiosk app for the CURRENT user: a systemd --user
# service serves web/ on 127.0.0.1:8080, and an XDG autostart entry opens it
# full-screen in Chrome at login. Safe to re-run (overwrites its own files
# only).
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"

if ! command -v google-chrome >/dev/null 2>&1; then
  echo "google-chrome not found on PATH. Install it first, or edit" >&2
  echo "blaster-kiosk-launch.sh afterwards to use a different browser." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found on PATH — needed to serve web/." >&2
  exit 1
fi

echo "Installing for user: $USER"
echo "Serving from: $WEB_DIR"

# 1. systemd --user service
mkdir -p "$HOME/.config/systemd/user"
sed "s|__WEB_DIR__|$WEB_DIR|" "$DEPLOY_DIR/blaster-web.service.template" \
  > "$HOME/.config/systemd/user/blaster-web.service"

systemctl --user daemon-reload
systemctl --user enable --now blaster-web.service

# 2. Launch script (kept outside the repo so it survives a `git clean`)
mkdir -p "$HOME/.local/bin"
cp "$DEPLOY_DIR/blaster-kiosk-launch.sh.template" "$HOME/.local/bin/blaster-kiosk-launch.sh"
chmod +x "$HOME/.local/bin/blaster-kiosk-launch.sh"

# 3. XDG autostart entry
mkdir -p "$HOME/.config/autostart"
sed "s|__LAUNCH_SCRIPT__|$HOME/.local/bin/blaster-kiosk-launch.sh|" \
  "$DEPLOY_DIR/blaster-kiosk.desktop.template" \
  > "$HOME/.config/autostart/blaster-kiosk.desktop"

echo
echo "Installed. Blaster will open full-screen the next time $USER logs in."
echo
echo "Try it now without logging out:"
echo "  systemctl --user status blaster-web.service   # confirm the server is up"
echo "  $HOME/.local/bin/blaster-kiosk-launch.sh &"
echo
echo "Uninstall with: $DEPLOY_DIR/uninstall-kiosk.sh"
