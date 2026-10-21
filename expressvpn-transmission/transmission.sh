#!/bin/bash
# Runs transmission while the VPN is usable (see vpn-ok); exits (so the container
# restarts) if the tunnel stays down. The daemon flaps (Disconnected/Connecting) for
# ~30s right after connecting, so ignore the first WATCHDOG_GRACE seconds and tolerate
# WATCHDOG_MISSES consecutive failed 10s checks. Network lock blocks leaks meanwhile.
WATCHDOG_GRACE=${WATCHDOG_GRACE:-90}
WATCHDOG_MISSES=${WATCHDOG_MISSES:-6}
# Force a reconnect every 2nd failed check: the client does not always notice a dead
# tunnel itself, and `connect` alone is a no-op while it still thinks it is Connected
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
    if vpn-ok; then
        down=0
    else
        down=$((down + 1))
        echo "[transmission] VPN not usable (${down}/${WATCHDOG_MISSES})"
        if [ $((down % WATCHDOG_RECONNECT)) -eq 0 ] && [ "$down" -lt "$WATCHDOG_MISSES" ]; then
            echo "[transmission] forcing VPN reconnect to ${SERVER:-smart}"
            timeout 15 expressvpnctl disconnect > /dev/null 2>&1 || true
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
