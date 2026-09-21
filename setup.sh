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
echo "[1/8] Installing dependencies (hdparm, tlp, tlp-rdw)..."
apt update
apt install -y hdparm tlp tlp-rdw

# 2. Setup server-mode
echo "[2/8] Installing /usr/local/bin/server-mode..."
cat << 'EOF' > /usr/local/bin/server-mode
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"

ENABLE_BT=false
ENABLE_SCREEN=false
ENABLE_HDD_SLEEP=false

for arg in "$@"; do
    case "$arg" in
        -b|--bt|--bluetooth) ENABLE_BT=true ;;
        -s|--screen) ENABLE_SCREEN=true ;;
        --hdd-sleep) ENABLE_HDD_SLEEP=true ;;
        -h|--help) server-help; exit 0 ;;
    esac
done

echo "==> Entering SERVER POWER-SAVE MODE..."
systemctl stop gdm3 2>/dev/null

# 1. Terminate desktop applications and GUI terminal sessions to reclaim RAM and CPU
# (Preserves remote SSH/Mosh sessions, Docker, and background system services)
echo " [*] Cleaning up desktop applications and GUI terminals..."
for u in $(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 {print $2}'); do
    killall -q -u "$u" brave brave-browser gnome-terminal-server 2>/dev/null || true
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

# HDD Management
if [ -b /dev/sda ]; then
    if [ "$ENABLE_HDD_SLEEP" = true ]; then
        hdparm -B 127 -S 120 /dev/sda > /dev/null 2>&1
        echo " [+] HDD       : AUTO-SLEEP (10 min spindown)"
    else
        hdparm -B 254 -S 0 /dev/sda > /dev/null 2>&1
        echo " [-] HDD       : ALWAYS-READY (No sleep spindown)"
    fi
fi

# CPU Governor & Energy Performance Preference
echo "powersave" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1
for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$epp" ] && echo "power" > "$epp" 2>/dev/null || true
done
echo "==> ACTIVE: Server mode running. Maximum RAM freed & CPU throttled to minimum."
EOF

# 3. Setup desktop-mode
echo "[3/8] Installing /usr/local/bin/desktop-mode..."
cat << 'EOF' > /usr/local/bin/desktop-mode
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"
echo "==> Restoring DESKTOP MODE..."

# 1. Restore Screen & Backlight
MAX_B=$(cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -n 1)
[ -n "$MAX_B" ] && echo "$MAX_B" | tee /sys/class/backlight/*/brightness > /dev/null 2>&1
setterm --blank poke < /dev/tty1 2>/dev/null || true

# 2. Unblock Bluetooth & CPU Performance
rfkill unblock bluetooth
systemctl start bluetooth 2>/dev/null
echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1
for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$epp" ] && echo "balance_performance" > "$epp" 2>/dev/null || true
done
hdparm -B 254 -S 0 /dev/sda > /dev/null 2>&1

# 3. Start or Restart Desktop Interface
if systemctl is-active --quiet gdm3; then
    systemctl restart gdm3
else
    systemctl start gdm3
fi
echo "==> ACTIVE: Desktop interface restored and screen backlight on."
EOF

# 4. Setup hardware toggles
echo "[4/8] Installing hardware toggle scripts..."
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
hdparm -B 127 -S 120 /dev/sda > /dev/null 2>&1
echo "HDD set to AUTO-SLEEP after 10 minutes idle."
EOF

cat << 'EOF' > /usr/local/bin/hdd-awake
#!/bin/bash
[ "$EUID" -ne 0 ] && exec sudo "$0" "$@"
hdparm -B 254 -S 0 /dev/sda > /dev/null 2>&1
echo "HDD set to ALWAYS-READY (No sleep/spindown)."
EOF

# 5. Setup status & help
echo "[5/8] Installing server-status and server-help..."
cat << 'EOF' > /usr/local/bin/server-status
#!/bin/bash
echo "==================== SERVER HARDWARE STATUS ===================="
if systemctl is-active --quiet gdm3; then
    echo "  Desktop (GNOME)   : [ ACTIVE / RUNNING ]"
else
    echo "  Desktop (GNOME)   : [ STOPPED (Headless) ]"
fi

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
HDD_STATE=$(hdparm -C /dev/sda 2>/dev/null | grep -oE "active/idle|standby|unknown")
[ -z "$HDD_STATE" ] && HDD_STATE=$(sudo -n hdparm -C /dev/sda 2>/dev/null | grep -oE "active/idle|standby|unknown" || echo "unknown (needs root)")

echo "  CPU Scaling       : [ $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null) ]"
echo "  CPU Load (1,5,15m): [ $CPU_LOAD ]"
echo "  RAM Usage         : [ $RAM_INFO ]"
echo "  HDD Drive State   : [ $HDD_STATE ]"
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
  desktop-mode             Restore full graphical GNOME desktop

[ DISK CONTROLS ]
  hdd-sleep                Enable 10m mechanical spindown on /dev/sda
  hdd-awake                Prevent spindown (zero lag for media/downloads)
  sudo hdparm -y /dev/sda  Force HDD into standby immediately
  sudo hdparm -C /dev/sda  Check if HDD is spinning or in standby

[ LIVE TOGGLES ]
  screen-on / screen-off   Toggle screen backlight ON or OFF
  bt-on / bt-off           Toggle Bluetooth radio ON or OFF

[ INSPECTION ]
  server-status            Show live state of all hardware & services
  server-help              Display this guide
===================================================================
HELP_EOF
EOF

# 6. Setup auto-idle-server.sh
echo "[6/8] Installing /usr/local/bin/auto-idle-server.sh (30m idle monitor)..."
cat << 'EOF' > /usr/local/bin/auto-idle-server.sh
#!/bin/bash
IDLE_THRESHOLD_MS=1800000
POLL_INTERVAL_SEC=30

while true; do
    sleep "$POLL_INTERVAL_SEC"

    # Only monitor if desktop is active
    if ! systemctl is-active --quiet gdm3; then
        continue
    fi

    ACTIVE_UID=""
    while read -r sid uid user seat tty state rest; do
        if [ "$seat" = "seat0" ] && [ "$state" = "active" ]; then
            CLASS=$(loginctl show-session "$sid" -p Class --value 2>/dev/null)
            if [ "$CLASS" = "user" ] && [ "$uid" -ge 1000 ]; then
                ACTIVE_UID="$uid"
                break
            fi
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)

    TARGET_UID=""
    if [ -n "$ACTIVE_UID" ]; then
        TARGET_UID="$ACTIVE_UID"
    else
        GDM_UID=$(id -u gdm 2>/dev/null)
        if [ -n "$GDM_UID" ] && [ -S "/run/user/$GDM_UID/bus" ]; then
            TARGET_UID="$GDM_UID"
        fi
    fi

    # Fail-safe: if target bus is unavailable, do nothing
    if [ -z "$TARGET_UID" ] || [ ! -S "/run/user/$TARGET_UID/bus" ]; then
        continue
    fi

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

    if [ "$IDLE_MS" -ge "$IDLE_THRESHOLD_MS" ]; then
        logger -t auto-idle-server "System idle >= 30m (${IDLE_MS}ms). Entering server-mode."
        /usr/local/bin/server-mode
    fi
done
EOF

# 7. Setup systemd service
echo "[7/8] Installing /etc/systemd/system/auto-idle-server.service..."
cat << 'EOF' > /etc/systemd/system/auto-idle-server.service
[Unit]
Description=Antigravity Auto-Idle Server Mode Switcher
After=multi-user.target gdm3.service
Wants=gdm3.service

[Service]
Type=simple
ExecStart=/usr/local/bin/auto-idle-server.sh
Restart=always
RestartSec=10
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

# 8. Set permissions and enable service
echo "[8/8] Setting permissions and enabling service..."
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
echo "==> Setup complete! auto-idle-server.service is enabled and active."
systemctl status auto-idle-server.service --no-pager
