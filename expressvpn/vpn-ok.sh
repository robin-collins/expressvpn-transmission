#!/bin/bash
# Exit 0 only if the VPN is really usable. The client keeps reporting "Connected" on a
# dead tunnel, so also require a request to get through. With network lock on, all
# non-VPN traffic is blocked, so a successful request can only have used the tunnel.
[ "$(expressvpnctl get connectionstate 2> /dev/null)" = "Connected" ] || exit 1
[ "$(expressvpnctl get networklock 2> /dev/null)" = "true" ] || exit 1
for url in ${VPN_CHECK_URLS:-https://1.1.1.1/cdn-cgi/trace https://dns.google/}; do
    curl -fsS -m 5 -o /dev/null "${url}" 2> /dev/null && exit 0
done
exit 1
