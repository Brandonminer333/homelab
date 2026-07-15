# Clavicus Vile — qBittorrent + Prowlarr + FlareSolverr (Proton VPN via Gluetun)

## Setup

qBittorrent password: `docker logs ClavicusVile 2>&1 | grep -i password`

Port-forward (WebUI via SSH): `ssh -L 8080:localhost:8080 -L 9696:localhost:9696 lenovoflakes -N`

- qBittorrent: http://localhost:8080
- Prowlarr: http://localhost:9696

## VPN port forwarding (Proton)

Requires a Plus-tier key with **NAT-PMP** enabled when generating the WireGuard config.
Gluetun sets `VPN_PORT_FORWARDING` + `PORT_FORWARD_ONLY` and pushes the assigned port into qBittorrent.
In qBittorrent WebUI options, enable **Bypass authentication for clients on localhost**.

Confirm: `docker logs ClavicusVile-vpn 2>&1 | grep -i "port forward"`

## Prowlarr links (same VPN network namespace → use localhost)

- Download client → qBittorrent: `http://127.0.0.1:8080`
- Indexer proxy → FlareSolverr: `http://127.0.0.1:8191`
