FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bluez \
    dbus \
    pulseaudio \
    pulseaudio-module-bluetooth \
    python3-dbus \
    python3-gi \
    alsa-utils \
    && rm -rf /var/lib/apt/lists/*

COPY main.conf /etc/bluetooth/main.conf
COPY system.pa /etc/pulse/system.pa
COPY entrypoint.sh /entrypoint.sh
COPY agent.py /agent.py

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
