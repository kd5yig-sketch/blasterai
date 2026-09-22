#!/usr/bin/env bash
# Reverses install-kiosk.sh for the current user. Leaves the kiosk Chrome
# profile (~/.local/share/blaster-kiosk-profile) in place so voice/settings
# survive a reinstall; pass --purge to remove it too.
set -euo pipefail

systemctl --user disable --now blaster-web.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/blaster-web.service"
systemctl --user daemon-reload

rm -f "$HOME/.config/autostart/blaster-kiosk.desktop"
rm -f "$HOME/.local/bin/blaster-kiosk-launch.sh"

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.local/share/blaster-kiosk-profile"
  echo "Removed the kiosk Chrome profile too."
fi

echo "Blaster kiosk uninstalled for $USER."
