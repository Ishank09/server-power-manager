# Server Power Manager & Auto-Idle

Lightweight power management and headless server mode switcher for Ubuntu / Debian laptop and desktop servers.

## Features

- **`server-mode`**:
  - Stops `gdm3` display manager.
  - Cleans up desktop applications (`brave`, `gnome-terminal-server`, and user `app.slice`) to reclaim ~2.5GB+ RAM and eliminate CPU wakeups.
  - Flushes kernel disk page caches and compacts memory.
  - Sets CPU scaling governor to `powersave` and energy performance preference to `power`.
  - Turns off display backlight (brightness 0) and disables Bluetooth.
  - Preserves remote SSH, Mosh, Docker, and background systemd services.
- **`desktop-mode`**:
  - Restores GNOME desktop interface and restarts `gdm3`.
  - Restores display backlight, unblocks Bluetooth, and sets CPU governor to `performance` / `balance_performance`.
- **`auto-idle-server`**:
  - Background systemd service monitoring Mutter idle time.
  - Automatically enters `server-mode` after 30 minutes of inactivity.
- **Hardware Toggles & Status**:
  - `screen-on` / `screen-off`
  - `bt-on` / `bt-off`
  - `hdd-sleep` / `hdd-awake`
  - `server-status`: Live overview of GUI state, backlight, Bluetooth, CPU load, RAM usage, and Docker containers.

## Installation

```bash
sudo bash setup.sh
```
