
# Run the ExpressVPN (v5+ headless, expressvpnctl) client in a container

FROM debian:trixie-slim

LABEL maintainer="benjamin@polkaned.net"

ENV SERVER=smart
ENV PROTOCOL=auto
ENV ACTIVATION_CODE_FILE=/run/secrets/expressvpn_activation_code
ENV CONNECT_RETRIES=5

ARG EXPRESSVPN_VERSION=14.2.0.13656
ARG EXPRESSVPN_RUN_URL=https://www.expressvpn.works/clients/linux/expressvpn-linux-universal-${EXPRESSVPN_VERSION}_release.run

RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl iproute2 iptables iputils-ping procps \
        libatomic1 libdbus-1-3 libglib2.0-0 xz-utils; \
    curl -fsSL "${EXPRESSVPN_RUN_URL}" -o /tmp/expressvpn.run; \
    sh /tmp/expressvpn.run --accept --quiet --noprogress -- --no-gui --sysvinit --force-dependencies; \
    rm -f /tmp/expressvpn.run; \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /tmp/entrypoint.sh
COPY --chmod=755 vpn-ok.sh /usr/local/bin/vpn-ok

ENTRYPOINT ["/bin/bash", "/tmp/entrypoint.sh"]
