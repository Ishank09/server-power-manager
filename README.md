# Server Power Manager & Auto-Idle

Lightweight power management and headless server mode switcher for Ubuntu / Debian laptop and desktop servers. Turn any spare laptop or desktop into a low-power, 24/7 headless home server with auto-idle switching and instant desktop restoration.

## Features

- **`server-mode`**:
  - **Universal Display Manager Shutdown:** Automatically detects and stops `gdm3`, `sddm`, `lightdm`, or `display-manager.service`.
  - **Aggressive RAM & CPU Reclamation:** Gracefully terminates GUI applications (`SIGTERM` followed by `SIGKILL`) and stops `app.slice`, freeing ~2.5GB+ of RAM and stopping background CPU timers.
  - **TLP Power Profile:** Activates `tlp bat` for deep PCIe ASPM (Active State Power Management), SATA link power-saving, and runtime USB autosuspend.
  - **Cache Purging & Compaction:** Flushes dirty disk page caches (`drop_caches=3`) and compacts RAM.
  - **CPU Power Throttling:** Locks scaling governor to `powersave` and energy performance preference to `power`.
  - **Mechanical HDD Auto-Sleep:** Automatically detects rotational disks (`/sys/block/*/queue/rotational`) and spins them down while leaving SSDs/NVMe drives untouched.
  - **Display & Radio Off:** Turns off backlight (brightness 0) and disables Bluetooth.
  - **Disconnected Ethernet Power-Down:** Powers down disconnected wired Ethernet interfaces (`NO-CARRIER`), saving ~0.5W-1.0W while leaving Wi-Fi, Tailscale, and Docker containers 100% active and untouched.
  - **Preserves Headless Services:** Keeps remote SSH, Mosh, Docker containers, Wi-Fi connectivity, and background system daemons online.
- **`desktop-mode`**:
  - Restores the graphical display manager.
  - Restores TLP AC profile, wakes up mechanical HDDs, unblocks Bluetooth, restores screen backlight, and brings wired Ethernet back up.
  - Switches CPU governor back to `performance` / `balance_performance`.
- **`auto-idle-server`**:
  - Background systemd service that tracks user desktop idle time via Mutter/DBus.
  - **Audio/Media Inactivity Safeguard:** Checks ALSA/kernel audio streams and defers switching to server mode if audio or media is actively playing (e.g. YouTube, Spotify, VLC).
  - Automatically enters `server-mode` when the system is inactive for a configurable duration.
- **Background Daemon & Indexer Trimming**:
  - **Prunes Inactive Daemons:** Stops and disables unused printing daemons (`cups`, `cups-browsed`) and cellular modem scanners (`ModemManager`).
  - **Stops Disk Indexing Crawler:** Masks GNOME Tracker3 (`tracker-miner-fs-3.service`) to eliminate unwanted background disk and CPU thrashing without breaking desktop search.
- **Laptop Hardware & Battery Protection**:
  - **Battery Charge Capping:** Configures TLP / SMBIOS to stop charging at **80%** (`/etc/tlp.d/01-battery.conf`), preventing battery swelling and wear during 24/7 plugged-in operation.
  - **Lid-Close Management:** Configures `systemd-logind` to ignore lid switches, allowing laptops to run 24/7 with the lid closed without suspending or spamming logind errors.
- **Hardware Toggles & Diagnostics**:
  - `screen-on` / `screen-off`: Control backlight on the fly.
  - `bt-on` / `bt-off`: Toggle Bluetooth radio.
  - `hdd-sleep` / `hdd-awake`: Control spindown across all rotational drives.
  - `server-status`: Real-time summary of desktop state, backlight, Bluetooth, CPU temperature, CPU load (1/5/15m), RAM usage, HDD spindown states, and Docker containers.

## Configuration

Settings can be customized in `/etc/server-power-manager.conf`:

```ini
# /etc/server-power-manager.conf

# Inactivity timeout (in minutes) before auto-switching to server mode
IDLE_TIMEOUT_MINUTES=30

# Automatically spin down mechanical HDDs in server mode (true/false)
ENABLE_HDD_SLEEP=true

# Keep Bluetooth enabled in server mode (true/false)
ENABLE_BLUETOOTH=false

# Keep Screen backlight enabled in server mode (true/false)
ENABLE_SCREEN=false
```

## Important Note on Window State & Memory Optimization

To guarantee true power savings and drop CPU/RAM usage to near zero, entering `server-mode` intentionally terminates all graphical applications and desktop terminal emulator sessions:

- **Windows are NOT preserved:** All open desktop windows, browser processes, and GUI terminal windows are closed to free up system memory (~2.5GB+ RAM) and prevent background CPU wakeups from running tabs or scripts.
- **Clean slate on desktop return:** When you run `desktop-mode`, your display manager initializes a clean, fresh desktop session. Previous windows will not reopen automatically.
- **Recommended Workflow:**
  - Run background CLI jobs and long-running processes inside **`tmux`**, **`screen`**, or remote **`ssh`** / **`mosh`** sessions—these run independently of the display server and stay active in server mode.
  - For browsers (e.g. Brave, Chrome), set startup settings to **"Continue where you left off"** to quickly restore tabs when reopening the browser in desktop mode.

## Installation

```bash
git clone https://github.com/Ishank09/server-power-manager.git
cd server-power-manager
sudo bash setup.sh
```

## Uninstallation

To cleanly remove all installed binaries, services, and logind configurations, and restore standard desktop behavior:

```bash
sudo bash uninstall.sh
```

## License

[MIT](LICENSE)
