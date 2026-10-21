#!/bin/bash
# Brings the VPN up (fail closed) and only then hands over to the CMD.
set -uo pipefail

log() { echo "[expressvpn] $*"; }

# Activation code: file (docker secret) preferred, ACTIVATION_CODE env as fallback
if [ -r "${ACTIVATION_CODE_FILE}" ]; then
    CODE=$(tr -d '[:space:]' < "${ACTIVATION_CODE_FILE}")
else
    CODE="${ACTIVATION_CODE:-}"
fi
if [ -z "${CODE}" ]; then
    log "No activation code (file ${ACTIVATION_CODE_FILE} or ACTIVATION_CODE)"
    exit 1
fi

# Docker bind-mounts resolv.conf; the VPN client needs to rewrite it
cp /etc/resolv.conf /tmp/resolv.conf
umount /etc/resolv.conf 2>/dev/null || true
cp /tmp/resolv.conf /etc/resolv.conf

svc=expressvpn-service
[ -f /etc/init.d/${svc} ] || svc=expressvpn
service ${svc} stop > /dev/null 2>&1 || true
service ${svc} start || { log "service ${svc} failed to start"; exit 1; }

for _ in $(seq 1 30); do
    timeout 5 expressvpnctl status > /dev/null 2>&1 && break
    sleep 2
done
timeout 5 expressvpnctl status > /dev/null 2>&1 || { log "daemon not responding"; exit 1; }

codefile=$(mktemp)
printf '%s' "${CODE}" > "${codefile}"
out=$(expressvpnctl --timeout 60 login "${codefile}" 2>&1)
rc=$?
rm -f "${codefile}"
if [ ${rc} -ne 0 ] && ! grep -qi "already logged into account" <<< "${out}"; then
    log "login failed: ${out}"
    exit 1
fi
expressvpnctl background enable > /dev/null 2>&1 || true

expressvpnctl set protocol "${PROTOCOL}" || log "could not set protocol ${PROTOCOL}"
expressvpnctl set allowlan true || log "could not set allowlan"
# Kill switch: block all non-VPN traffic if the tunnel drops
expressvpnctl set networklock true || { log "could not enable network lock"; exit 1; }

connected() { [ "$(expressvpnctl get connectionstate 2> /dev/null)" = "Connected" ]; }

for attempt in $(seq 1 "${CONNECT_RETRIES}"); do
    log "connecting to ${SERVER} (attempt ${attempt}/${CONNECT_RETRIES})"
    expressvpnctl connect "${SERVER}" && break
    sleep 10
done
for _ in $(seq 1 30); do connected && break; sleep 2; done
connected || { log "VPN not connected, refusing to start workload"; exit 1; }
for _ in $(seq 1 15); do vpn-ok && break; sleep 2; done
vpn-ok || { log "no traffic through the tunnel, refusing to start workload"; exit 1; }
log "connected"

exec "$@"
