# any-phone-output

Makes this machine behave like a Bluetooth speaker. Phones discover it, pair without a PIN, and stream audio via A2DP.

## Prerequisites

- Bluetooth adapter present on the host
- Docker + Docker Compose

```bash
# Verify adapter is visible to the kernel
hciconfig
```

BlueZ does **not** need to be installed on the host — the container runs its own `bluetoothd`.

## Start

```bash
docker compose up -d
docker compose logs -f
```

The device broadcasts as **"Any Phone Output"**. Open Bluetooth settings on any phone, find it, and tap to pair — no PIN required.

## Stop

```bash
docker compose down
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `SPEAKER_NAME` | `Any Phone Output` | Name shown to pairing devices |

Change it in `docker-compose.yml` under `environment`.

## Reliable reconnection (no daily re-pairing)

Phones rotate their Bluetooth link keys over time. By default BlueZ refuses a
peer whose key no longer matches the stored bond — the connection fails with
`Permission denied (13)` on AVDTP, and you're forced to "forget" the device and
pair again. This setup avoids that:

- **`main.conf`** sets `JustWorksRepairing = always`, so a device whose key has
  diverged silently re-bonds through the auto-accept agent — no human action.
- Devices are marked **`Trusted`** automatically (on connect via `agent.py`, and
  on startup for already-bonded devices via `entrypoint.sh`), so reconnects
  auto-authorize instead of racing the agent.

This is a BlueZ *bonding* concern, not an audio one — switching the audio stack
(PipeWire, bluez-alsa) would not change it, since they all pair through BlueZ.

## Audio output

The container tries to load the host's default ALSA device (`hw:0`). If no sound card is detected, it falls back to a null sink (audio is received but discarded). To use a specific card:

```yaml
# docker-compose.yml
environment:
  PULSE_ALSA_DEVICE: "hw:1"  # override card index
```

Or edit `system.pa` and add `device=hw:X` to the `module-alsa-sink` line.

## Troubleshooting

**Device not discoverable:**
```bash
docker compose exec bluetooth-speaker bluetoothctl show
```

**No audio after pairing:**
```bash
docker compose exec bluetooth-speaker pactl list sinks short
docker compose exec bluetooth-speaker pactl list sources short
```

**PulseAudio conflict with host:**  
If the host is running a PulseAudio user session that has already claimed the Bluetooth A2DP profile, stop it first:
```bash
systemctl --user stop pulseaudio.socket pulseaudio.service
```

**Phone asks for a PIN / can't reconnect:**  
With `JustWorksRepairing = always` (see [Reliable reconnection](#reliable-reconnection-no-daily-re-pairing)) a key mismatch normally self-heals on the next connect. If a bond is genuinely wedged, remove it on the speaker side and re-pair. List, inspect, and remove bonds with `bluetoothctl`:
```bash
# List paired devices
docker compose exec bluetooth-speaker bluetoothctl devices Paired

# Inspect one
docker compose exec bluetooth-speaker bluetoothctl info <MAC>

# Remove a bond (cleans both the filesystem record and runtime state)
docker compose exec bluetooth-speaker bluetoothctl remove <MAC>
```
After removing, also "forget" the speaker on the phone, then pair again.

Bonds are stored in `./bt-bonds/` on the host (bind-mounted to `/var/lib/bluetooth/` in the container) — they survive `docker compose down`. To wipe all bonds, delete the folder: `sudo rm -rf ./bt-bonds`.
