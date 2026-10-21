# 2026-10-22: Transmission ran without the VPN (IP leak), and the fixes

Times are UTC (local Adelaide = UTC+10:30). Host: `ralph`. Stack: Portainer stack **150**
(`transmission`), container `transmission`.

## TL;DR

- The running container was **not** this repo's fail-closed build. It was the
  **2023 Docker Hub image** (`speeddemonau/expressvpn-transmission:latest`, Hub digest
  `sha256:81c4ffae…`, pushed 2023-10-27). ExpressVPN activation **failed** inside it, and
  Transmission **started anyway, torrenting on the home IP `<home WAN IP>`**.
- The container was stopped at about 15:22 (it had been up since 15:17:03, so the leak
  lasted at most about 5 minutes for this start).
- Root cause: the 10-17 fail-closed rewrite was only ever built locally under the tag
  `:latest`. A stack redeploy with image re-pull (around 15:15–15:17, right after the
  activation-code file was edited at 15:15) replaced it with Hub's stale `:latest`.
- A second, independent bug was found in the new code during testing: the watchdog trusted
  `expressvpnctl get connectionstate`, which **keeps saying `Connected` on a dead tunnel**.
  So the container would never restart in that case. This is fixed and verified.
- The stack now has to use the `:local` tag with `pull_policy: never` (see
  `/home/tech/transmission/docker-compose.yml`). **The stack has not been redeployed yet. It is
  still on the v5 definition and the container is stopped.**

## 1. What was found on the running container

`docker inspect` / `docker logs transmission`:

| Item | Value |
|---|---|
| Image | `sha256:ea8377e7…`, created 2023-10-27, RepoDigest = Hub `latest` |
| Started | 2026-10-21T15:17:03Z, RestartCount 0, policy `unless-stopped`, no healthcheck |
| Client | old ExpressVPN 3.x CLI (`expressvpn activate` via an `expect` script) |

Log excerpt (old image):

```
umount: /etc/resolv.conf: must be superuser to unmount.
Activating...
Activation failed.
This activation code has either expired or is incorrect. ...
send: spawn id exp3 not open   (expect script crashed)
Please activate your account.  (x4, connect attempts)
Transmission 3.00 (bb6b5a062e) started          <-- started regardless
RPC Server Serving RPC and Web requests on 0.0.0.0:9091
DHT Bootstrapping from 292 IPv4 nodes          <-- peer traffic on the real IP
Port Forwarding (NAT-PMP) ... succeeded        <-- tried to open a port on the home router
```

Leak confirmed directly:

```
host egress:      <home WAN IP>
container egress: <home WAN IP>     <-- same, no tunnel
ip addr: only lo + eth0 (no tun0); `expressvpn status` = "Not Activated"
```

Action taken: `docker stop transmission` (reversible; the stack definition was not touched).

## 2. Root cause: the image source

- `speeddemonau/expressvpn:latest` was rebuilt locally on 10-17 (commit `69e0764`), but
  **nothing was ever pushed to Docker Hub**. Hub's `:latest` for both repos is still
  2023-10-27.
- The stack uses `image: speeddemonau/expressvpn-transmission:latest`. Any Portainer
  redeploy with "re-pull image" (or a `docker compose pull`) silently swaps the local
  fail-closed image for Hub's old one. The container's RepoDigest matches Hub exactly,
  which shows this is what happened.
- `/home/tech/transmission/expressvpn_activation_code` was modified at 15:15 UTC and the
  container was created at 15:17:02. That points to a code rotation followed by a
  redeploy that pulled.
- The activation code itself is **fine**. The new v5 client (`expressvpnctl login`)
  accepted it on the first try. The old 3.x client rejected it ("expired or incorrect").

### Fix

- Images are now built and referenced as **`:local`**, a tag that does **not** exist on
  Docker Hub (verified: Hub returns 404 for both repos). `build_local.sh` builds
  `speeddemonau/expressvpn:local`, then `speeddemonau/expressvpn-transmission:local`.
  The child `Dockerfile` uses `FROM speeddemonau/expressvpn:local`.
- The compose files use `pull_policy: never`. A pull now **fails** loudly instead of
  quietly downgrading.
- The local `:latest` tags were also retagged to the verified `:local` image (`1d78ef4c9d37`),
  so a no-pull redeploy of the old v5 definition gets the safe image too. A **pull** of
  `:latest` would still fetch the 2023 image, so don't use `:latest` at all.

## 3. Second bug: the watchdog was blind to a dead tunnel

Found while testing the new build (the 10-17 version, before today's fix) in a throwaway
container `vpntest`:

1. Startup: activation OK, connected in about 4s, egress `45.133.5.74` (ExpressVPN), DNS
   `100.64.100.1` (through the tunnel), no IPv6 egress, network-lock iptables/ip6tables
   chains present.
2. Ran `ip link set tun0 down` to kill the tunnel without telling the client:
   - **Kill switch OK.** Egress was `BLOCKED` the whole time; no leak.
   - **Watchdog FAILED.** `expressvpnctl get connectionstate` stayed `Connected` for 3+
     minutes on a dead tunnel. The watchdog never counted a miss and never restarted.
     Transmission would have sat "running" forever with no connectivity. This broke the
     "connect OR restart" requirement.
3. Ran `expressvpnctl disconnect` and checked egress again: still `BLOCKED` (network lock
   holds during a user disconnect). `connect` then restored the tunnel. So
   disconnect-then-connect is a safe recovery action. A plain `connect` (what the
   watchdog used to send) does nothing while the client believes it is connected.

### Fix

- New `expressvpn/vpn-ok.sh`, installed as `/usr/local/bin/vpn-ok`. It succeeds only if
  **all** of these hold:
  1. `connectionstate` = `Connected`
  2. `networklock` = `true`
  3. an HTTPS request gets through (`https://1.1.1.1/cdn-cgi/trace`, falling back to
     `https://dns.google/`; override with `VPN_CHECK_URLS`). With network lock on,
     non-VPN traffic is blocked, so a successful request can only have gone through
     the tunnel.
- `entrypoint.sh`: after `Connected`, it also requires `vpn-ok` (up to about 30s) before it
  `exec`s the workload. Otherwise it exits 1.
- `transmission.sh` watchdog: uses `vpn-ok`, and on every 2nd miss does
  `expressvpnctl disconnect` followed by `connect`.
- `HEALTHCHECK` now runs `vpn-ok`.

## 4. Verification of the fixed image (`:local`, `1d78ef4c9d37`)

All tests ran in a throwaway container with the same caps, device and secret as the
stack, scratch volumes, and `WATCHDOG_GRACE=20` to save time.

| Test | Method | Result |
|---|---|---|
| Normal start | fresh container | connected in ~5s, egress 45.133.5.x, Transmission up, health `healthy` |
| Dead tunnel, recoverable | `ip link set tun0 down` | 2 misses, forced reconnect, traffic restored after about 25s; egress was BLOCKED until then, never the home IP |
| Tunnel blackholed with iptables | `iptables -I OUTPUT 1 -o tun0 -j DROP` | **Did not test the restart path as intended**: the forced reconnect rebuilds the client's firewall rules and removed the test rule, so it recovered (fine behaviour, but not the test I wanted) |
| Unrecoverable (daemon hung) | `kill -STOP` both ExpressVPN daemon processes, `--restart unless-stopped` | 6/6 misses and 2 forced reconnects (about 1m50s), then the watchdog exited and Docker restarted the container. Egress was BLOCKED during the gap. Fresh start connected at 15:38:26, Transmission up, `vpn-ok` PASS, RestartCount 1 |

The test container `vpntest` was removed afterwards. The scratch volumes were in the session
scratchpad, not in `/home/tech`.

Worst-case time from tunnel loss to restart, with default settings: `WATCHDOG_GRACE` (90s,
only right after startup) plus 6 misses at about 15–25s each (10s sleep + probe timeouts +
reconnect attempts), so roughly 2–2.5 minutes. **Network lock blocks all non-VPN traffic
during that window**, so a slow restart costs downtime, not privacy.

## 5. Things that went wrong / were wrong during this work

- The README banners said the container "restarts if the tunnel stays down for 30s".
  That was never accurate (90s grace + 6×10s checks), and it was moot anyway because of the
  dead-tunnel blindness. Corrected.
- The first `build_local.sh` run today produced `:latest` images **without** the
  `vpn-ok` fix (`d3c2d844935e`). They were used only for testing, and `:latest` was later
  retagged to the fixed image.
- The iptables-blackhole test (table above) did not exercise the restart path. A second
  method (`SIGSTOP`) was needed.
- The first attempt to back up `/home/tech/transmission/config` failed (`tar: Permission
  denied`: `settings.json`/`stats.json` are root-owned). It was redone as root via a
  container: `/home/tech/transmission/config.pre-tr4.bak-20261022.tar.gz`.
- Harmless log noise, left alone: `umount: /etc/resolv.conf: must be superuser`
  (the entrypoint falls back to copying over the bind mount, and DNS inside the tunnel was
  verified working). Transmission's UDP buffer warnings (`net.core.rmem_max`) are a host
  sysctl matter and only affect performance.

## 6. Not done / needs a decision

- ~~Redeploy the stack~~: done by the user at 15:41:34 UTC, see section 7.
- Transmission jumps from **3.00 to 4.1.0-beta.2** (Debian trixie package) with the new
  image. 4.x upgrades `settings.json`/resume files in place. A backup was taken first
  (above). Note that it is a beta build.
- Docker Hub `speeddemonau/expressvpn*:latest` still serves the unsafe 2023 image to anyone
  who pulls it. Options: push the fixed images, or delete or deprecate those tags. Not done
  (outward-facing).
- `expressvpn-transmission/build.sh` and `build_and_push.sh` are upstream leftovers that push
  to `polkaned/*`. Unused and untouched.
- `T_ALLOWED=*.*.*.*` with no `T_USERNAME`/`T_PASSWORD` in the stack means the RPC/web UI
  has no auth, behind Traefik on the LAN-only `https` entrypoint. Pre-existing, left as is.

## 7. After the redeploy (user redeployed stack 150 with the new file)

Checked at about 15:45 UTC: the container runs `speeddemonau/expressvpn-transmission:local`
(`1d78ef4c9d37`), health `healthy`, `vpn-ok` PASS, egress `45.133.5.146` (ExpressVPN). The log
shows `[expressvpn] connected` before Transmission started.

Two things the user reported after the redeploy. Both turned out harmless:

- **`Couldn't read '.../torrents/8295bfa6….torrent'`**: `queue.json` (last written
  2026-10-18) still lists that torrent, but `torrents/` and `resume/` were already empty
  (emptied 2026-10-21 14:58 UTC, before this incident). It's a stale queue entry. Transmission
  skips it and rewrites `queue.json` on its next save. No data lost by this work.
- **Missing toolbar icons in the web UI, plus `Couldn't read .../style/transmission/images/toolbar-*.png`**:
  Transmission 4.x ships a completely new web UI (`index.html`, `transmission-app.css/js`,
  no `style/` dir). Through Traefik, the new `index.html`, CSS and JS all load fine (200), and
  none of them reference `toolbar-*.png`. Those requests come from the **browser's
  cached 3.00 web UI**. Fix: hard-refresh (Ctrl+Shift+R), or clear site data for
  `transmission.homelab.teamcollins.net`. Same for any other browser or device that had
  the old UI open. Nothing to change server-side.
