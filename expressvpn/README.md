> **Updated for the ExpressVPN v5+ headless client (`expressvpnctl`).**
> The old `ACTIVATION_CODE` env / `--privileged` examples below no longer apply:
> - Put the activation code alone in a file and mount it as the docker secret `expressvpn_activation_code`
>   (`/run/secrets/expressvpn_activation_code`). Rotate it by editing the file and restarting the container.
>   `ACTIVATION_CODE` env is still read as a fallback.
> - Required: `cap_add: [NET_ADMIN, SYS_PTRACE]` and `/dev/net/tun`. No `privileged` needed.
> - Network lock (kill switch) is always enabled, the entrypoint refuses to start the workload unless the VPN
>   is connected, and the transmission image exits (container restarts) if the tunnel stays down for 30s.
> - See `expressvpn-transmission/docker-compose-example.yaml` and `build_local.sh`.

# ExpressVPN in a container

This container should be used as base layer.

## Prerequisites

1. Get your activation code from ExpressVPN web site.

## Download

`docker pull polkaned/expressvpn`

## Start the container

    docker run \
      --env=ACTIVATION_CODE={% your-activation-code %} \
      --env=SERVER={% LOCATION/ALIAS/COUNTRY %} \
      --env=PREFERRED_PROTOCOL={% protocol %} \
      --env=LIGHTWAY_CIPHER={% lightway-cipher %} \
      --cap-add=NET_ADMIN \
      --device=/dev/net/tun \
      --privileged \
      --detach=true \
      --tty=true \
      --name=expressvpn \
      polkaned/expressvpn \
      /bin/bash


## Docker Compose
Other containers can use the network of the expressvpn container by declaring the entry `network_mode: service:expressvpn`.
In this case all traffic is routed via the vpn container. To reach the other containers locally the port forwarding must be done in the vpn container (the network mode service does not allow a port configuration)

  ```
  expressvpn:
    container_name: expressvpn
    image: polkaned/expressvpn
    environment:
      - ACTIVATION_CODE={% your-activation-code %}
      - SERVER={% LOCATION/ALIAS/COUNTRY %}
      - PREFERRED_PROTOCOL={% protocol %}
      - LIGHTWAY_CIPHER={% lightway-cipher %}
    cap_add:
      - NET_ADMIN
    devices: 
      - /dev/net/tun
    stdin_open: true
    tty: true
    command: /bin/bash
    privileged: true
    restart: unless-stopped
    ports:
      # ports of other containers that use the vpn (to access them locally)
  
  downloader:
    image: example/downloader
    container_name: downloader
    network_mode: service:expressvpn
    depends_on:
      - expressvpn
  ```

## Configuration Reference

### ACTIVATION_CODE
A mandatory string containing your ExpressVPN activation code.

`ACTIVATION_CODE=ABCD1EFGH2IJKL3MNOP4QRS`

### SERVER
A optional string containing the ExpressVPN server LOCATION/ALIAS/COUNTRY. Connect to smart location if it is not set.

`SERVER=ukbe`

### PREFERRED_PROTOCOL
A optional string containing the ExpressVPN protocol. Can be auto, udp, tcp ,lightway_udp, lightway_tcp. Use auto if it is not set.

`PREFERRED_PROTOCOL=lightway_udp`

### LIGHTWAY_CIPHER
A optional string containing the ExpressVPN lightway cipher. Can be auto, aes, chacha20. Use auto if it is not set.

`LIGHTWAY_CIPHER=chacha20`
