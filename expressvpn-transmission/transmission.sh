#!/bin/bash
# Runs transmission while the VPN is connected; exits (so the container restarts)
# if the tunnel stays down.

param=(--allowed "${T_ALLOWED}")
param+=(--foreground)
param+=(--encryption-preferred)
param+=(--incomplete-dir /var/lib/transmission-daemon/downloads)
param+=(--dht)
param+=(--download-dir /var/lib/transmission-daemon/downloads)
if [ -n "$T_USERNAME" ] && [ -n "$T_PASSWORD" ]
then
    param+=(--auth --username "${T_USERNAME}" --password "${T_PASSWORD}")
else
    param+=(--no-auth)
fi

/usr/bin/transmission-daemon "${param[@]}" &
pid=$!
trap 'kill "$pid" 2>/dev/null; wait "$pid"; exit 0' TERM INT

down=0
while kill -0 "$pid" 2>/dev/null; do
    if [ "$(expressvpnctl get connectionstate 2>/dev/null)" = "Connected" ]; then
        down=0
    else
        down=$((down + 1))
        echo "[transmission] VPN not connected (${down}/3)"
        if [ "$down" -ge 3 ]; then
            kill "$pid" 2>/dev/null
            wait "$pid"
            exit 1
        fi
    fi
    sleep 10
done
wait "$pid"
