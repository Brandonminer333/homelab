# Clavicus Vile — qBittorrent + Prowlarr + FlareSolverr (Proton VPN via Gluetun)

## Setup

qBittorrent password: `docker logs ClavicusVile 2>&1 | grep -i password`

Port-forward: `ssh -L 8080:localhost:8080 -L 9696:localhost:9696 lenovoflakes -N`

- qBittorrent: http://localhost:8080
- Prowlarr: http://localhost:9696

## Prowlarr links (same VPN network namespace → use localhost)

- Download client → qBittorrent: `http://127.0.0.1:8080`
- Indexer proxy → FlareSolverr: `http://127.0.0.1:8191`
