# Choppy Audio / Latency Diagnosis

*Diagnosed 2026-07-03, streaming from "Richard's MacBook Pro" (`AC:07:75:2D:85:8D`) at ~15ft.*

## Symptom

Intermittent choppy playback and growing latency during Bluetooth A2DP streaming.

## Diagnosis

**The Bluetooth radio link is weak, and PulseAudio underruns because of it.** Container logs confirm:

```
W: module-loopback.c: Too many underruns, increasing latency to 205.00 ms
W: module-loopback.c: Too many underruns, increasing latency to 215.00 ms
```

Each underrun is an audible gap — that's the choppiness. PulseAudio keeps growing its
loopback buffer to compensate, which is why perceived latency creeps up over a session.

Measured link quality to the connected device: **148 / 255** (`hcitool lq`) — a good link
at this distance should be near 255. Negotiated codec: SBC (fine; bandwidth is not the
bottleneck — RF link quality is).

Three factors stack up:

1. **Weak internal radio.** The adapter is an Intel 7265 combo card (USB `8087:0a2a`) —
   Bluetooth 4.x sharing one internal laptop antenna with Wi-Fi. Weakest link at 15ft.
   Host Wi-Fi is on 5GHz (so 2.4GHz spectrum overlap isn't the main issue), but the
   shared-antenna coexistence logic can still throttle Bluetooth.
2. **Permanently discoverable.** `entrypoint.sh` re-enables `discoverable on` every 60s,
   even mid-stream. Inquiry scan steals radio time from the audio (ACL) link and is a
   known cause of A2DP glitches.
3. **Small adaptive buffer.** The auto-created `module-loopback` starts at ~200ms and only
   grows *after* audible underruns, then resets on every reconnect.

## Fixes, in order of bang-for-buck

1. **USB Bluetooth 5.x dongle with an external antenna** (~$15–20). The real fix —
   replaces the weak internal radio, gets its own antenna away from Wi-Fi, and BT 5 has
   much better range. Point BlueZ at `hci1` (or disable the internal adapter).
2. **Skip the discoverable refresh while a device is connected** — small change to the
   `entrypoint.sh` refresh loop so the radio isn't burning time on inquiry scans during
   playback.
3. **Disable Wi-Fi/BT coexistence throttling on the host** — Wi-Fi is 5GHz-only, so
   `options iwlwifi bt_coex_active=0` in `/etc/modprobe.d/` is safe and often noticeably
   smooths Bluetooth audio on Intel combo cards.
4. **Start the loopback with a bigger buffer** (e.g. 500ms) so brief RF hiccups get
   absorbed instead of heard. Trade-off: audio lags the source by ~0.5s — fine for music,
   bad for video sync.

Fixes 2–4 are software-only but won't fully fix a 148/255 link; the dongle is what
actually solves it at 15ft.

## Useful diagnostic commands

```bash
# Link quality to a connected device (0–255, want ~255)
docker exec bluetooth-speaker hcitool lq <MAC>

# Negotiated codec and source latency
docker exec bluetooth-speaker pactl list sources | grep -E 'bluetooth.codec|Latency'

# Underrun history
docker logs bluetooth-speaker 2>&1 | grep -i underrun
```
