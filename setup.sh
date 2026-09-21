#!/bin/bash
set -e

# Ensure running with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (e.g. sudo bash setup.sh)"
    exit 1
fi

echo "================================================================="
echo "   Setting up Server / Desktop Power Management & Auto-Idle"
echo "================================================================="

# 1. Install required packages
echo "[1/10] Installing dependencies (hdparm, tlp, tlp-rdw, smbios-utils)..."
apt update
apt install -y hdparm tlp tlp-rdw smbios-utils
systemctl enable --now tlp 2>/dev/null || true

# 2. Configure battery protection (80% stop threshold for 24/7 AC power)
echo "[2/10] Configuring battery charge threshold (80% stop) to protect battery longevity..."
mkdir -p /etc/tlp.d
cat << 'EOF' > /etc/tlp.d/01-battery.conf
# Battery charging threshold for 24/7 AC plugged-in operation
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
EOF
if command -v smbios-battery-ctl >/dev/null 2>&1; then
    smbios-battery-ctl --set-charging-mode=primarily-ac-use 2>/dev/null || true
fi
systemctl restart tlp 2>/dev/null || true
echo " [+] Battery charge threshold active (caps charge at 80% to prevent swelling)."

# 3. Setup configuration file
echo "[3/10] Installing default configuration in /etc/server-power-manager.conf..."
if [ ! -f /etc/server-power-manager.conf ]; then
    cat << 'EOF' > /etc/server-power-manager.conf
# /etc/server-power-manager.conf
# Configuration for Server Power Manager & Auto-Idle

# Inactivity timeout (in minutes) before auto-switching to server mode
IDLE_TIMEOUT_MINUTES=30

# Automatically spin down mechanical HDDs in server mode (true/false)
ENABLE_HDD_SLEEP=true

# Keep Bluetooth enabled in server mode (true/false)
ENABLE_BLUETOOTH=false

# Keep Screen backlight enabled in server mode (true/false)
ENABLE_SCREEN=false
EOF
    echo " [+] Created /etc/server-power-manager.conf"
else
    echo " [.] Existing /etc/server-power-manager.conf preserved."
fi

# 4. Setup laptop lid-close behavior (ignore lid close to prevent unintended suspend)
echo "[4/10] Configuring clean laptop lid-close behavior..."
mkdir -p /etc/systemd/logind.conf.d
cat << 'EOF' > /etc/systemd/logind.conf.d/server-lid.conf
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
systemctl kill -s HUP systemd-logind 2>/dev/null || true
echo " [+] Laptop lid-close set to ignore (no logind suspend spam)."

# 5. Setup server-mode
echo "[5/10] Installing /usr/local/bin/server-mode..."
cat << 'EOF' > /usr/local/bin/server-mode
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"

# Load configuration if available
[ -f /etc/server-power-manager.conf ] && . /etc/server-power-manager.conf

ENABLE_BT=${ENABLE_BLUETOOTH:-false}
ENABLE_SCREEN=${ENABLE_SCREEN:-false}
ENABLE_HDD_SLEEP=${ENABLE_HDD_SLEEP:-false}

for arg in "$@"; do
    case "$arg" in
        -b|--bt|--bluetooth) ENABLE_BT=true ;;
        -s|--screen) ENABLE_SCREEN=true ;;
        --hdd-sleep) ENABLE_HDD_SLEEP=true ;;
        -h|--help) server-help; exit 0 ;;
    esac
done

echo "==> Entering SERVER POWER-SAVE MODE..."

# Universal display manager shutdown
for dm in display-manager gdm3 gdm sddm lightdm; do
    if systemctl is-active --quiet "$dm" 2>/dev/null; then
        systemctl stop "$dm" 2>/dev/null || true
    fi
done

# 1. Gracefully terminate desktop applications and GUI terminal sessions
# (Preserves remote SSH/Mosh sessions, Docker, and background system services)
echo " [*] Gracefully terminating desktop applications and GUI terminals..."
for u in $(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 {print $2}'); do
    pkill -TERM -u "$u" -f "brave|chrome|chromium|gnome-terminal-server" 2>/dev/null || true
done
sleep 2
for u in $(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 {print $2}'); do
    pkill -KILL -u "$u" -f "brave|chrome|chromium|gnome-terminal-server" 2>/dev/null || true
    systemctl --user -M "${u}@" stop app.slice 2>/dev/null || true
done

# 2. Flush disk caches and compact memory
echo " [*] Flushing disk caches and compacting memory..."
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true

# Bluetooth
if [ "$ENABLE_BT" = true ]; then
    rfkill unblock bluetooth && systemctl start bluetooth 2>/dev/null
    echo " [+] Bluetooth : ON"
else
    rfkill block bluetooth && systemctl stop bluetooth 2>/dev/null
    echo " [-] Bluetooth : OFF"
fi

# Screen
if [ "$ENABLE_SCREEN" = true ]; then
    setterm --blank poke < /dev/tty1 2>/dev/null || true
    MAX_B=$(cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -n 1)
    [ -n "$MAX_B" ] && echo "$((MAX_B / 2))" | tee /sys/class/backlight/*/brightness > /dev/null 2>&1
    echo " [+] Screen    : ON"
else
    setterm --blank force < /dev/tty1 2>/dev/null || true
    echo 0 | tee /sys/class/backlight/*/brightness > /dev/null 2>&1
    echo " [-] Screen    : OFF"
fi

# Mechanical HDD Management (Auto-detects rotational drives)
for devpath in /sys/block/sd* /sys/block/hd*; do
    if [ -f "$devpath/queue/rotational" ] && [ "$(cat "$devpath/queue/rotational" 2>/dev/null)" = "1" ]; then
        disk="/dev/$(basename "$devpath")"
        if [ "$ENABLE_HDD_SLEEP" = true ]; then
            hdparm -B 127 -S 120 "$disk" > /dev/null 2>&1
            echo " [+] HDD ($disk) : AUTO-SLEEP (10 min spindown)"
        else
            hdparm -B 254 -S 0 "$disk" > /dev/null 2>&1
            echo " [-] HDD ($disk) : ALWAYS-READY (No sleep spindown)"
        fi
    fi
done

# CPU Governor & Energy Performance Preference
echo "powersave" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1
for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$epp" ] && echo "power" > "$epp" 2>/dev/null || true
done

# TLP Power Profile (PCIe ASPM & SATA Link Power Management)
if command -v tlp >/dev/null 2>&1; then
    tlp bat >/dev/null 2>&1 || true
    echo " [+] Power Profile: TLP Low-Power / ASPM Active"
fi
echo "==> ACTIVE: Server mode running. Maximum RAM freed & CPU throttled to minimum."
EOF

# 6. Setup desktop-mode
echo "[6/10] Installing /usr/local/bin/desktop-mode..."
cat << 'EOF' > /usr/local/bin/desktop-mode
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"
echo "==> Restoring DESKTOP MODE..."

# 1. Restore Screen & Backlight
MAX_B=$(cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -n 1)
[ -n "$MAX_B" ] && echo "$MAX_B" | tee /sys/class/backlight/*/brightness > /dev/null 2>&1
setterm --blank poke < /dev/tty1 2>/dev/null || true

# 2. Unblock Bluetooth, Restore TLP AC Profile & CPU Performance
rfkill unblock bluetooth
systemctl start bluetooth 2>/dev/null
if command -v tlp >/dev/null 2>&1; then
    tlp ac >/dev/null 2>&1 || true
fi
echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1
for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$epp" ] && echo "balance_performance" > "$epp" 2>/dev/null || true
done

# 3. Wake up mechanical HDDs
for devpath in /sys/block/sd* /sys/block/hd*; do
    if [ -f "$devpath/queue/rotational" ] && [ "$(cat "$devpath/queue/rotational" 2>/dev/null)" = "1" ]; then
        disk="/dev/$(basename "$devpath")"
        hdparm -B 254 -S 0 "$disk" > /dev/null 2>&1
    fi
done

# 4. Start Desktop Interface (Display Manager)
for dm in display-manager gdm3 gdm sddm lightdm; do
    if systemctl is-active --quiet "$dm" 2>/dev/null; then
        systemctl restart "$dm" 2>/dev/null && break
    elif systemctl is-enabled --quiet "$dm" 2>/dev/null; then
        systemctl start "$dm" 2>/dev/null && break
    fi
done
systemctl start display-manager 2>/dev/null || systemctl start gdm3 2>/dev/null || true

echo "==> ACTIVE: Desktop interface restored and screen backlight on."
EOF

# 7. Setup hardware toggles
echo "[7/10] Installing hardware toggle scripts..."
cat << 'EOF' > /usr/local/bin/screen-on
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"
MAX_B=$(cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -n 1)
[ -n "$MAX_B" ] && echo "$((MAX_B / 2))" | tee /sys/class/backlight/*/brightness > /dev/null 2>&1
setterm --blank poke < /dev/tty1 2>/dev/null || true
echo "Screen turned ON."
EOF

cat << 'EOF' > /usr/local/bin/screen-off
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"
setterm --blank force < /dev/tty1 2>/dev/null || true
echo 0 | tee /sys/class/backlight/*/brightness > /dev/null 2>&1
echo "Screen turned OFF."
EOF

cat << 'EOF' > /usr/local/bin/bt-on
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"
rfkill unblock bluetooth && systemctl start bluetooth 2>/dev/null
echo "Bluetooth turned ON."
EOF

cat << 'EOF' > /usr/local/bin/bt-off
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"
rfkill block bluetooth && systemctl stop bluetooth 2>/dev/null
echo "Bluetooth turned OFF."
EOF

cat << 'EOF' > /usr/local/bin/hdd-sleep
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"
FOUND=false
for devpath in /sys/block/sd* /sys/block/hd*; do
    if [ -f "$devpath/queue/rotational" ] && [ "$(cat "$devpath/queue/rotational" 2>/dev/null)" = "1" ]; then
        disk="/dev/$(basename "$devpath")"
        hdparm -B 127 -S 120 "$disk" > /dev/null 2>&1
        echo "HDD ($disk) set to AUTO-SLEEP after 10 minutes idle."
        FOUND=true
    fi
done
[ "$FOUND" = false ] && echo "No rotational mechanical HDDs detected (SSDs/NVMe skipped)."
EOF

cat << 'EOF' > /usr/local/bin/hdd-awake
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"
FOUND=false
for devpath in /sys/block/sd* /sys/block/hd*; do
    if [ -f "$devpath/queue/rotational" ] && [ "$(cat "$devpath/queue/rotational" 2>/dev/null)" = "1" ]; then
        disk="/dev/$(basename "$devpath")"
        hdparm -B 254 -S 0 "$disk" > /dev/null 2>&1
        echo "HDD ($disk) set to ALWAYS-READY (No spindown)."
        FOUND=true
    fi
done
[ "$FOUND" = false ] && echo "No rotational mechanical HDDs detected (SSDs/NVMe skipped)."
EOF

# 8. Setup status & help
echo "[8/10] Installing server-status and server-help..."
cat << 'EOF' > /usr/local/bin/server-status
#!/bin/bash
echo "==================== SERVER HARDWARE STATUS ===================="
DM_ACTIVE=false
for dm in display-manager gdm3 gdm sddm lightdm; do
    if systemctl is-active --quiet "$dm" 2>/dev/null; then
        echo "  Desktop ($dm)  : [ ACTIVE / RUNNING ]"
        DM_ACTIVE=true
        break
    fi
done
[ "$DM_ACTIVE" = false ] && echo "  Desktop (GUI)     : [ STOPPED (Headless Server) ]"

BRIGHTNESS=$(cat /sys/class/backlight/*/brightness 2>/dev/null | head -n 1)
if [ "$BRIGHTNESS" = "0" ]; then
    echo "  Screen Backlight  : [ OFF ]"
else
    echo "  Screen Backlight  : [ ON ]"
fi

if rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: yes"; then
    echo "  Bluetooth Radio   : [ OFF ]"
else
    echo "  Bluetooth Radio   : [ ON ]"
fi

RAM_INFO=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2 " used"}')
CPU_LOAD=$(awk '{print $1 ", " $2 ", " $3}' /proc/loadavg 2>/dev/null)
CPU_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")

CPU_TEMP=""
for tz in /sys/class/thermal/thermal_zone*; do
    type=$(cat "$tz/type" 2>/dev/null)
    if [ "$type" = "x86_pkg_temp" ] || [ "$type" = "cpu-thermal" ] || [ "$type" = "acpitz" ]; then
        raw_temp=$(cat "$tz/temp" 2>/dev/null)
        if [ -n "$raw_temp" ] && [ "$raw_temp" -gt 0 ]; then
            celsius=$((raw_temp / 1000))
            if [ "$celsius" -ge 80 ]; then
                CPU_TEMP="${celsius}°C (HIGH)"
            else
                CPU_TEMP="${celsius}°C"
            fi
            break
        fi
    fi
done

echo "  CPU Scaling       : [ $CPU_GOV ]"
echo "  CPU Load (1,5,15m): [ $CPU_LOAD ]"
[ -n "$CPU_TEMP" ] && echo "  CPU Temperature   : [ $CPU_TEMP ]"
echo "  RAM Usage         : [ $RAM_INFO ]"

for devpath in /sys/block/sd* /sys/block/hd*; do
    if [ -f "$devpath/queue/rotational" ] && [ "$(cat "$devpath/queue/rotational" 2>/dev/null)" = "1" ]; then
        disk="/dev/$(basename "$devpath")"
        state=$(hdparm -C "$disk" 2>/dev/null | grep -oE "active/idle|standby|unknown")
        [ -z "$state" ] && state=$(sudo -n hdparm -C "$disk" 2>/dev/null | grep -oE "active/idle|standby|unknown" || echo "unknown")
        echo "  HDD ($disk)   : [ $state ]"
    fi
done

echo "  Docker Containers : [ $(docker ps -q 2>/dev/null | wc -l) running ]"
echo "================================================================"
EOF

cat << 'EOF' > /usr/local/bin/server-help
#!/bin/bash
cat << "HELP_EOF"
===================================================================
                   SERVER / DESKTOP MODE CHEAT SHEET
===================================================================
[ MODES ]
  server-mode              Headless 24/7 server (GUI, Screen, BT OFF; HDD ready)
  server-mode --hdd-sleep  Headless 24/7 server + mechanical HDD 10m spindown
  server-mode --bt         Headless server, but keep Bluetooth ON
  server-mode --screen     Headless server, but keep Screen ON
  desktop-mode             Restore full graphical desktop

[ CONFIGURATION ]
  /etc/server-power-manager.conf  Set idle timer, default BT/screen/HDD modes

[ DISK CONTROLS ]
  hdd-sleep                Enable 10m mechanical spindown on detected HDDs
  hdd-awake                Prevent spindown (zero lag for media/downloads)
  sudo hdparm -y /dev/sdX  Force specific HDD into standby immediately
  sudo hdparm -C /dev/sdX  Check if HDD is spinning or in standby

[ LIVE TOGGLES ]
  screen-on / screen-off   Toggle screen backlight ON or OFF
  bt-on / bt-off           Toggle Bluetooth radio ON or OFF

[ INSPECTION ]
  server-status            Show live state of all hardware & services
  server-help              Display this guide
===================================================================
HELP_EOF
EOF

# 9. Setup auto-idle-server.sh & service
echo "[9/10] Installing /usr/local/bin/auto-idle-server.sh (Dynamic idle monitor)..."
cat << 'EOF' > /usr/local/bin/auto-idle-server.sh
#!/bin/bash

POLL_INTERVAL_SEC=60

while true; do
    sleep "$POLL_INTERVAL_SEC"

    # 1. Fast check: Only monitor if desktop is active; if already in headless server mode, skip immediately
    if ! systemctl is-active --quiet display-manager gdm3 2>/dev/null; then
        continue
    fi

    # 2. Read configuration
    IDLE_MINS=30
    [ -f /etc/server-power-manager.conf ] && . /etc/server-power-manager.conf
    IDLE_THRESHOLD_MS=$(( ${IDLE_TIMEOUT_MINUTES:-30} * 60 * 1000 ))

    # 3. Find active user DBus target without heavy subprocess scraping
    TARGET_UID=""
    for u in 1000 $(id -u gdm 2>/dev/null); do
        if [ -S "/run/user/$u/bus" ]; then
            TARGET_UID="$u"
            break
        fi
    done
    [ -z "$TARGET_UID" ] && continue

    IDLE_MS=$(sudo -u "#$TARGET_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
        gdbus call --session \
        --dest org.gnome.Mutter.IdleMonitor \
        --object-path /org/gnome/Mutter/IdleMonitor/Core \
        --method org.gnome.Mutter.IdleMonitor.GetIdletime 2>/dev/null \
        | grep -oE '[0-9]+' | head -n 1)

    # Fail-safe: never trigger server mode on query error or empty response
    if [ -z "$IDLE_MS" ]; then
        continue
    fi

    # 4. Threshold reached: check audio safeguard on-demand ONLY, then enter server mode
    if [ "$IDLE_MS" -ge "$IDLE_THRESHOLD_MS" ]; then
        # Audio Safeguard: only checked when idle time threshold is met, never polled while active
        if grep -q "state: RUNNING" /proc/asound/card*/pcm*/sub*/status 2>/dev/null; then
            continue
        fi

        logger -t auto-idle-server "System idle >= ${IDLE_TIMEOUT_MINUTES:-30}m (${IDLE_MS}ms). Entering server-mode."
        /usr/local/bin/server-mode
    fi
done
EOF

cat << 'EOF' > /etc/systemd/system/auto-idle-server.service
[Unit]
Description=Server Power Manager Auto-Idle Monitor
After=multi-user.target
Wants=display-manager.service

[Service]
Type=simple
ExecStart=/usr/local/bin/auto-idle-server.sh
Restart=always
RestartSec=10
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

# 10. Set permissions and enable service
echo "[10/10] Setting permissions and enabling service..."
chmod +x /usr/local/bin/server-mode \
         /usr/local/bin/desktop-mode \
         /usr/local/bin/screen-on \
         /usr/local/bin/screen-off \
         /usr/local/bin/bt-on \
         /usr/local/bin/bt-off \
         /usr/local/bin/hdd-sleep \
         /usr/local/bin/hdd-awake \
         /usr/local/bin/server-status \
         /usr/local/bin/server-help \
         /usr/local/bin/auto-idle-server.sh

systemctl daemon-reload
systemctl enable --now auto-idle-server.service

echo ""
echo "================================================================="
echo "==> Setup complete! auto-idle-server.service is enabled and active."
echo "==> Config file: /etc/server-power-manager.conf"
echo "================================================================="
systemctl status auto-idle-server.service --no-pager
