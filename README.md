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

## Important Note on Window State & Memory Optimization

To guarantee true power savings and drop CPU/RAM usage to near zero, entering `server-mode` intentionally terminates all graphical applications and desktop terminal emulator sessions:

- **Windows are NOT preserved:** All open desktop windows, browser processes, and GUI terminal windows are closed to free up system memory (~2.5GB+ RAM) and prevent background CPU wakeups from running tabs or scripts.
- **Clean slate on desktop return:** When you run `desktop-mode`, GNOME initializes a clean, fresh desktop session. Previous windows will not reopen automatically.
- **Recommended Workflow:**
  - Run background CLI jobs and long-running processes inside **`tmux`**, **`screen`**, or remote **`ssh`** / **`mosh`** sessions—these run independently of the display server and will stay active in server mode.
  - For browsers (e.g. Brave, Chrome), set startup settings to **"Continue where you left off"** to quickly restore tabs when reopening the browser in desktop mode.

## Installation

```bash
sudo bash setup.sh
```

## License

[MIT](LICENSE)
