<!-- SPDX-License-Identifier: Apache-2.0 -->
# Kiosk deployment

Installs Blaster to run full-screen, automatically, for one Linux user —
the shape a dedicated AAC device needs. Built for and tested against Ubuntu
26.04 + Cinnamon + LightDM + systemd (this machine's setup); the pieces
(`systemd --user`, XDG autostart, Chrome `--kiosk`) are standard enough to
work on most systemd-based desktop distros with minor adjustment.

## What gets installed

Running `./install-kiosk.sh` as the target user sets up three things, all
scoped to that user (nothing system-wide, nothing needs root):

1. **`~/.config/systemd/user/blaster-web.service`** — runs
   `python3 -m http.server` over `web/`, bound to `127.0.0.1:8080` only
   (never exposed on the network). Enabled to start with the user's
   graphical session.
2. **`~/.local/bin/blaster-kiosk-launch.sh`** — waits for that server to
   answer, then launches Chrome in kiosk mode
   (`--kiosk --app=http://127.0.0.1:8080`), fullscreen with no address bar,
   tabs, or window chrome, using its own Chrome profile
   (`~/.local/share/blaster-kiosk-profile`) so it's isolated from any other
   Chrome profile on the machine and its `localStorage` (settings, sentence
   cache) survives restarts.
3. **`~/.config/autostart/blaster-kiosk.desktop`** — an XDG autostart entry
   that runs the launch script when that user logs into their desktop
   session.

## Install

```bash
web/deploy/install-kiosk.sh
```

Log out and back in (or run the two commands the script prints) to see it
without waiting for a reboot.

## Uninstall

```bash
web/deploy/uninstall-kiosk.sh
```

Add `--purge` to also delete the kiosk's Chrome profile.

## The escape hatch

For a caregiver, not the child: **Alt+F4** closes the kiosk window like any
other window — Chrome's `--kiosk` flag removes browser chrome, it doesn't
disable the window manager. That drops back to the desktop. If your distro
image locks down window-manager shortcuts for the child's account, decide
separately how a caregiver gets back in (a different user account is the
usual answer, sudo-capable, that never runs the kiosk autostart entry).

To stop the app without leaving the session:

```bash
systemctl --user stop blaster-web.service
pkill -f blaster-kiosk-launch.sh   # or close the Chrome window
```

## Updating

`git pull` in the repo, then re-run `scripts/convert_tiles.sh` if art
changed. No service restart needed — `http.server` reads files fresh on
each request. Reload the Chrome window (or restart it) to pick up changed
JS/HTML/CSS, since kiosk mode has no reload button — cycle it with:

```bash
pkill -f blaster-kiosk-launch.sh
~/.local/bin/blaster-kiosk-launch.sh &
```

## Adapting to a different init system or desktop

- **Not systemd?** Replace `blaster-web.service` with whatever your init
  starts on session begin — the command it needs to run is just
  `python3 -m http.server 8080 --bind 127.0.0.1 --directory <path to web/>`.
- **Not XDG autostart-compatible?** Any "run this at login" mechanism works
  — the target is just `~/.local/bin/blaster-kiosk-launch.sh`.
- **Not Chrome?** Firefox supports a comparable `-kiosk` flag
  (`firefox -kiosk http://127.0.0.1:8080`), though its kiosk mode is less
  complete (no separate `--app`-style profile isolation flag — use
  `-profile <dir>` instead) and some newer flags above are Chrome-only.
  **Avoid Brave**: verified 2026-09-22 that Brave implements the Web Speech
  API but never populates a voice list, so the app loads and navigates fine
  but every tap is silent with no error — Chrome and Firefox both speak
  correctly on the same machine. If you're adapting this for a
  Chromium-based browser other than stock Chrome, check
  `speechSynthesis.getVoices().length` in its devtools console before
  assuming it'll work.
- **A dedicated single-purpose device** (boots straight into the kiosk, no
  visible desktop at all) needs one more layer: an auto-login display
  manager config for the kiosk user (e.g. LightDM's
  `autologin-user=<name>` in `/etc/lightdm/lightdm.conf`, which needs root)
  on top of everything here. Ask if you want that wired up too — it's a
  system-wide change so worth doing deliberately rather than folding into
  this per-user installer.
