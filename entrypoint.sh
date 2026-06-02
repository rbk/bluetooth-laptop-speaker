#!/bin/bash
set -e

SPEAKER_NAME="${SPEAKER_NAME:-Any Phone Output}"

echo "[bt-speaker] Starting as: $SPEAKER_NAME"

# Clear stale runtime state from prior unclean exits — without this,
# dbus-daemon refuses to start ("pid file exists") and the container
# enters a restart loop, since /run is part of the writable layer.
rm -f /run/dbus/pid /run/dbus/system_bus_socket /var/run/pulse/pid

# D-Bus system daemon — needed by bluetoothd and PulseAudio
mkdir -p /var/run/dbus
dbus-daemon --system --fork
echo "[bt-speaker] D-Bus started"

# BlueZ
/usr/lib/bluetooth/bluetoothd --nodetach &
echo "[bt-speaker] Waiting for bluetoothd..."
for i in $(seq 1 15); do
    bluetoothctl show 2>/dev/null | grep -q "Controller" && break
    sleep 1
done
echo "[bt-speaker] bluetoothd ready"

# PulseAudio — registers A2DP sink profile with BlueZ via D-Bus
pulseaudio --system --disallow-exit --no-cpu-limit --log-level=notice &
sleep 3

# Configure the adapter
bluetoothctl power on
bluetoothctl pairable on
bluetoothctl discoverable on
bluetoothctl system-alias "$SPEAKER_NAME" 2>/dev/null || \
    bluetoothctl set-alias "$SPEAKER_NAME"

echo "[bt-speaker] Adapter ready. Discoverable as: $SPEAKER_NAME"

# BlueZ resets Discoverable after 180s — keep refreshing
(while true; do
    bluetoothctl discoverable on >/dev/null 2>&1 || true
    bluetoothctl pairable on   >/dev/null 2>&1 || true
    sleep 60
done) &

echo "[bt-speaker] Auto-pairing agent running"
exec python3 /agent.py
