
# Run expressvpn and transmission in a container

FROM speeddemonau/expressvpn:local
LABEL maintainer="benjamin@polkaned.net"

ENV T_ALLOWED=127.0.0.1
ENV T_USERNAME=
ENV T_PASSWORD=

RUN apt-get update && apt-get install -y --no-install-recommends \
    transmission-daemon \
    && rm -rf /var/lib/apt/lists/*

COPY transmission.sh /tmp/transmission.sh

HEALTHCHECK --start-period=60s --interval=30s --timeout=10s --retries=3 \
    CMD vpn-ok

CMD ["/bin/bash", "/tmp/transmission.sh"]
