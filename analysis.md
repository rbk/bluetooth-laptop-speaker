# Architecture & Design Analysis

## How it works

```
Phone (A2DP source)
  └─ Bluetooth radio
       └─ Host BlueZ (bluetoothd via systemd)
            └─ D-Bus (shared socket: /var/run/dbus)
                 ├─ agent.py  ← auto-accepts pairing & service auth
                 └─ PulseAudio (system mode, in container)
                      └─ module-bluetooth-discover  ← claims A2DP sink profile
                           └─ module-bluetooth-policy  ← routes phone audio → sink
                                └─ ALSA sink (hw:0) or null sink
```

## Key design decisions

### Why run our own bluetoothd instead of sharing the host's?

The host has no `bluetooth.service` / BlueZ installed. The container runs its own `dbus-daemon` (system bus), `bluetoothd`, PulseAudio, and the pairing agent — all self-contained. They communicate over an internal D-Bus socket at `/var/run/dbus/system_bus_socket` inside the container, which has the correct BlueZ and PulseAudio D-Bus policy files because both packages are installed inside the image.

This is actually cleaner than sharing the host bus: no dependency on host state, no risk of policy mismatches, fully reproducible.

### Why PulseAudio in system mode?

PulseAudio's `module-bluetooth-discover` registers as the A2DP profile handler with BlueZ over D-Bus. Running it in system mode (`--system`) connects to the system bus, which is the same bus bluetoothd uses — so they can find each other even though PulseAudio is inside Docker.

User-mode PulseAudio would connect to a session D-Bus, which doesn't exist in the container.

### Why `JustWorksRepairing = always` + trust-on-connect?

Phones rotate their link keys, so a stored bond eventually stops matching what
the phone presents. BlueZ's default repairing policy (`never`) rejects this and
fails A2DP with `Permission denied (13)` on AVDTP, forcing a manual forget +
re-pair — the "re-pair daily" symptom. Setting `JustWorksRepairing = always` in
`main.conf` lets the NoInputNoOutput agent silently re-bond instead.

Devices are also marked `Trusted` (in `agent.py` on connect, and in
`entrypoint.sh` for pre-existing bonds) so reconnects auto-authorize.

Crucially this lives entirely in **BlueZ**, the pairing/bonding layer — every
audio backend below (PulseAudio, PipeWire, bluez-alsa) bonds through BlueZ, so
swapping the audio stack would not have fixed reconnection.

### Why `--privileged`?

Required for:
- HCI socket access (Bluetooth hardware layer)
- ALSA device access via `/dev/snd`
- `bluetoothctl` to issue adapter commands

`network_mode: host` is required because Bluetooth isn't namespaced in Linux — it's always host-level.

## Known limitations

### Discoverable timeout
BlueZ resets `Discoverable` to off after 180 seconds by default. The entrypoint runs a background loop that re-enables it every 60 seconds. Once paired, a phone can reconnect without needing discovery — so this only affects first-time pairing.

### Single PulseAudio instance
If the host is already running PulseAudio (desktop machine with a user session), both instances will try to claim the A2DP profile from BlueZ. Whichever registers first wins. On a headless server (this machine), there's no competing PulseAudio, so no issue.

### Audio output
The container tries to open ALSA `hw:0`. If the machine has no sound card (common for servers), the ALSA module fails silently and falls back to a null sink. To actually hear audio, the host needs a real sound card.

### No re-pairing guard
The agent accepts all requests unconditionally — any device can pair. This is intentional for the use case ("any phone") but means there's no access control.

## Alternatives considered

| Approach | Pro | Con |
|---|---|---|
| `bluez-alsa` (bluealsad) | Lighter, purpose-built for BT audio | Not in standard Ubuntu repos, needs PPA or build from source; same BlueZ bonding layer, so no effect on reconnection reliability |
| PipeWire | Modern, handles BT natively; fewer stream underruns than PA system-mode | More complex config, newer distro required; same BlueZ bonding layer |
| Run own bluetoothd in container | Self-contained | Conflicts with host daemon, needs to stop host service |
| `bt-agent` from bluez-tools | One-line pairing agent | Doesn't explicitly handle `AuthorizeService`, less reliable for A2DP |

PulseAudio was chosen: standard Ubuntu packages, well-documented A2DP support, handles `AuthorizeService` through `module-bluetooth-policy`.
