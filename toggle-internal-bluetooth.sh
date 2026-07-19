#!/bin/bash
# Enable/disable the internal Intel Bluetooth radio (USB 8087:0a2a) that this
# host's combo Wi-Fi/BT card exposes. It shares a single antenna with Wi-Fi
# and caused choppy A2DP audio at range — see choppy-audio-diagnosis.md.
# Disabling it keeps BlueZ from ever picking it as the default controller
# instead of the external USB dongle, regardless of USB enumeration order.
set -euo pipefail

VENDOR_ID="8087"
PRODUCT_ID="0a2a"
UDEV_RULE="/etc/udev/rules.d/99-disable-internal-bt.rules"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/toggle-internal-bluetooth.log"

# Mirror all output to a log file (world-readable) so it can be reviewed
# after the fact — this is normally run interactively with sudo, outside
# of any session that could otherwise capture its output directly.
touch "$LOG_FILE" 2>/dev/null || true
chmod 666 "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') toggle-internal-bluetooth.sh ${1:-} ==="

usage() {
    echo "Usage: $0 {disable|enable|status}"
    echo
    echo "  disable  Deauthorize the internal BT radio now and install a udev"
    echo "           rule so it stays disabled across reboots and replugs."
    echo "  enable   Remove the udev rule and reauthorize the radio now."
    echo "  status   Show whether the rule is installed and the device's"
    echo "           current authorization state."
    exit 1
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Must be run with sudo (needs to write /etc/udev/rules.d and /sys)." >&2
        exit 1
    fi
}

find_device_path() {
    local d v p
    for d in /sys/bus/usb/devices/*/; do
        if [ -f "${d}idVendor" ] && [ -f "${d}idProduct" ]; then
            v=$(cat "${d}idVendor" 2>/dev/null || true)
            p=$(cat "${d}idProduct" 2>/dev/null || true)
            if [ "$v" = "$VENDOR_ID" ] && [ "$p" = "$PRODUCT_ID" ]; then
                echo "${d%/}"
                return 0
            fi
        fi
    done
    return 1
}

do_status() {
    if [ -f "$UDEV_RULE" ]; then
        echo "udev rule: present ($UDEV_RULE) — internal BT stays disabled across reboots/replugs"
    else
        echo "udev rule: absent — internal BT is free to bind on next plug/boot"
    fi

    local dev_path
    if dev_path=$(find_device_path); then
        if [ "$(cat "$dev_path/authorized")" = "1" ]; then
            echo "device: attached and authorized (active)"
        else
            echo "device: attached but deauthorized (disabled)"
        fi
    else
        echo "device: not currently attached"
    fi
}

do_disable() {
    require_root
    cat > "$UDEV_RULE" <<EOF
# Disable the internal Intel Bluetooth radio (combo Wi-Fi/BT card, USB ${VENDOR_ID}:${PRODUCT_ID}).
# Weak single shared antenna caused choppy A2DP audio at range — see
# choppy-audio-diagnosis.md. Replaced by an external BT USB dongle.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${VENDOR_ID}", ATTR{idProduct}=="${PRODUCT_ID}", ATTR{authorized}="0"
EOF
    udevadm control --reload-rules
    echo "Installed udev rule: $UDEV_RULE"

    local dev_path
    if dev_path=$(find_device_path); then
        echo 0 > "$dev_path/authorized"
        echo "Deauthorized attached device at $dev_path"
    else
        echo "No device currently attached; rule will apply on next plug/boot."
    fi
}

do_enable() {
    require_root
    if [ -f "$UDEV_RULE" ]; then
        rm -f "$UDEV_RULE"
        udevadm control --reload-rules
        echo "Removed udev rule: $UDEV_RULE"
    else
        echo "No udev rule present."
    fi

    local dev_path
    if dev_path=$(find_device_path); then
        echo 1 > "$dev_path/authorized"
        echo "Reauthorized device at $dev_path"
    else
        echo "No device currently attached; it will bind normally on next plug/boot."
    fi
}

case "${1:-}" in
    disable) do_disable ;;
    enable) do_enable ;;
    status) do_status ;;
    *) usage ;;
esac
