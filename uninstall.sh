#!/bin/bash
set -e

# Ensure running with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (e.g. sudo bash uninstall.sh)"
    exit 1
fi

echo "================================================================="
echo "   Uninstalling Server / Desktop Power Manager"
echo "================================================================="

# 1. Stop and disable auto-idle service
echo "[1/5] Stopping and removing auto-idle-server.service..."
if systemctl is-active --quiet auto-idle-server.service 2>/dev/null; then
    systemctl stop auto-idle-server.service 2>/dev/null || true
fi
if systemctl is-enabled --quiet auto-idle-server.service 2>/dev/null; then
    systemctl disable auto-idle-server.service 2>/dev/null || true
fi
rm -f /etc/systemd/system/auto-idle-server.service

# 2. Remove logind lid configuration
echo "[2/5] Removing laptop lid-close configuration..."
rm -f /etc/systemd/logind.conf.d/server-lid.conf
systemctl kill -s HUP systemd-logind 2>/dev/null || true

# 3. Remove installed binaries
echo "[3/5] Removing scripts from /usr/local/bin..."
rm -f /usr/local/bin/server-mode \
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

# 4. Remove config files
echo "[4/5] Removing configuration files..."
rm -f /etc/server-power-manager.conf
rm -f /etc/tlp.d/01-battery.conf
systemctl restart tlp 2>/dev/null || true

# 5. Restore default desktop & CPU governor
echo "[5/5] Restoring default hardware state..."
rfkill unblock bluetooth 2>/dev/null || true
systemctl start bluetooth 2>/dev/null || true

MAX_B=$(cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -n 1)
[ -n "$MAX_B" ] && echo "$MAX_B" | tee /sys/class/backlight/*/brightness > /dev/null 2>&1

echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1
for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -f "$epp" ] && echo "balance_performance" > "$epp" 2>/dev/null || true
done

for dm in display-manager gdm3 gdm sddm lightdm; do
    if systemctl is-enabled --quiet "$dm" 2>/dev/null; then
        systemctl start "$dm" 2>/dev/null || true
        break
    fi
done

systemctl daemon-reload
echo ""
echo "==> Uninstallation complete! All files and services have been removed."
