#!/bin/bash
# Runs transmission while the VPN is connected; exits (so the container restarts)
# if the tunnel stays down. The daemon flaps (Disconnected/Connecting) for ~30s right
# after connecting, so ignore the first WATCHDOG_GRACE seconds and tolerate
# WATCHDOG_MISSES consecutive failed 10s checks. Network lock blocks leaks meanwhile.
WATCHDOG_GRACE=${WATCHDOG_GRACE:-90}
WATCHDOG_MISSES=${WATCHDOG_MISSES:-6}
# Ask the client to reconnect (it does not always do so itself) every 2nd failed check
WATCHDOG_RECONNECT=${WATCHDOG_RECONNECT:-2}

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
sleep "$WATCHDOG_GRACE" & wait $!
while kill -0 "$pid" 2>/dev/null; do
    if [ "$(expressvpnctl get connectionstate 2>/dev/null)" = "Connected" ]; then
        down=0
    else
        down=$((down + 1))
        echo "[transmission] VPN not connected (${down}/${WATCHDOG_MISSES})"
        if [ $((down % WATCHDOG_RECONNECT)) -eq 0 ] && [ "$down" -lt "$WATCHDOG_MISSES" ]; then
            echo "[transmission] requesting VPN reconnect to ${SERVER:-smart}"
            timeout 30 expressvpnctl connect "${SERVER:-smart}" > /dev/null 2>&1 || true
        fi
        if [ "$down" -ge "$WATCHDOG_MISSES" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid"
            exit 1
        fi
    fi
    sleep 10 & wait $!
done
wait "$pid"
