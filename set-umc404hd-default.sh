#!/usr/bin/env bash
set -euo pipefail

CARD="U192k"
ASOUNDRC="${HOME}/.asoundrc"

read -r -d '' DESIRED <<EOF || true
pcm.!default {
    type plug
    slave.pcm "hw:${CARD},0"
}

ctl.!default {
    type hw
    card ${CARD}
}
EOF

if ! aplay -l 2>/dev/null | grep -q "card [0-9]\+: ${CARD} "; then
    echo "error: ALSA card '${CARD}' not found. Is the UMC404HD plugged in?" >&2
    aplay -l >&2 || true
    exit 1
fi

if [[ ! -f "${ASOUNDRC}" ]] || [[ "$(cat "${ASOUNDRC}")" != "${DESIRED}" ]]; then
    if [[ -f "${ASOUNDRC}" ]]; then
        cp "${ASOUNDRC}" "${ASOUNDRC}.bak.$(date +%s)"
        echo "backed up existing ${ASOUNDRC}"
    fi
    printf '%s\n' "${DESIRED}" > "${ASOUNDRC}"
    echo "wrote ${ASOUNDRC} (default = plughw:${CARD},0)"
else
    echo "${ASOUNDRC} already correct"
fi

amixer -c "${CARD}" sset 'UMC404HD 192k Output',0 100% unmute >/dev/null
amixer -c "${CARD}" sset 'UMC404HD 192k Output',1 100% unmute >/dev/null
echo "volume set to 100% on card ${CARD}"
