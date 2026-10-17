> **Updated for the ExpressVPN v5+ headless client (`expressvpnctl`).**
> The old `ACTIVATION_CODE` env / `--privileged` examples below no longer apply:
> - Put the activation code alone in a file and mount it as the docker secret `expressvpn_activation_code`
>   (`/run/secrets/expressvpn_activation_code`). Rotate it by editing the file and restarting the container.
>   `ACTIVATION_CODE` env is still read as a fallback.
> - Required: `cap_add: [NET_ADMIN, SYS_PTRACE]` and `/dev/net/tun`. No `privileged` needed.
> - Network lock (kill switch) is always enabled, the entrypoint refuses to start the workload unless the VPN
>   is connected, and the transmission image exits (container restarts) if the tunnel stays down for 30s.
> - See `expressvpn-transmission/docker-compose-example.yaml` and `build_local.sh`.

# ExpressVPN and Transmission in a container

## Prerequisites

1. Get your activation code from ExpressVPN web site.

## Download

`docker pull polkaned/expressvpn-transmission`

## Start the container

    docker run \
      --volume=/home/user/Torrents:/var/lib/transmission-daemon/downloads \
      --env=ACTIVATION_CODE={% your-activation-code %} \
    [ --env=SERVER={% LOCATION/ALIAS/COUNTRY %} \]
    [ --env=T_ALLOWED={% your-allowed-ip-list %} \]
    [ --env=T_USERNAME={% your-username %} \
      --env=T_PASSWORD={% your-password %} \]
      --cap-add=NET_ADMIN \
      --device=/dev/net/tun \
      --privileged \
      --detach=true \
      --tty=true \
    [ -p 9091:9091 \]
      --name=expressvpn-transmission \
      polkaned/expressvpn-transmission

## Configuration

### Mount the downloads Volume
Mount a downloads volume to the host for the Transmission working directories (incomplete and download).

`--volume=/home/user/Torrents:/var/lib/transmission-daemon/downloads`

### ACTIVATION_CODE
A mandatory string containing your ExpressVPN activation code.

`ACTIVATION_CODE=ABCD1EFGH2IJKL3MNOP4QRS`

### SERVER
A optional string containing the ExpressVPN server LOCATION/ALIAS/COUNTRY. Connect to smart location if it is not set.

`SERVER=ukbe`

### T_ALLOWED
A optional string containing the Transmission IP addresses' whitelist. 127.0.0.1 is not set. Use `*` for wildcards.

`T_ALLOWED=127.0.0.1,172.17.0.1,192.168.0.*`

### T_USERNAME & T_PASSWORD
Optional strings containing the Transmission username and password if you want to authenticate. There is no authentication if not set.

    T_USERNAME=admin
    T_PASSWORD=********
