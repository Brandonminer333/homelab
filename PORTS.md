# Homelab ports

Hostname: `lenovoflakes.tail62b305.ts.net` (Tailscale MagicDNS).

## Public (Tailscale / host-published)

| Port  | Service              | Stack       | Access |
|-------|----------------------|-------------|--------|
| 80    | HTTP → HTTPS         | nginx       | redirect to `:443` |
| 443   | Homepage             | nginx → homepage | `https://lenovoflakes.tail62b305.ts.net/` |
| 8443  | Jellyfin             | nginx → jellyfin | `https://lenovoflakes.tail62b305.ts.net:8443/` |
| 8444  | Nextcloud            | nginx → nextcloud | `https://lenovoflakes.tail62b305.ts.net:8444/` |
| 8445  | Pi-hole admin        | nginx → pihole | `https://lenovoflakes.tail62b305.ts.net:8445/admin/` |
| 8446  | Navidrome            | nginx → navidrome | `https://lenovoflakes.tail62b305.ts.net:8446/` |
| 8447  | Vaultwarden          | nginx → vaultwarden | `https://lenovoflakes.tail62b305.ts.net:8447/` |
| 8448  | Collabora            | nginx → collabora | `https://lenovoflakes.tail62b305.ts.net:8448/` |
| 2586  | ntfy                 | ntfy        | `http://lenovoflakes.tail62b305.ts.net:2586` |

Nextcloud reuses Seafile's old `:8444`; the upstream-recommended `:8080` is already
taken by qBittorrent. CalDAV/CardDAV clients use
`https://lenovoflakes.tail62b305.ts.net:8444/remote.php/dav` (was Radicale on `:8450`).

## Localhost-only (SSH tunnel)

| Port | Service       | Stack       | Notes |
|------|---------------|-------------|-------|
| 8080 | qBittorrent   | qbittorrent | behind Gluetun; `ssh -L 8080:localhost:8080 …` |
| 9696 | Prowlarr      | qbittorrent | behind Gluetun; `ssh -L 9696:localhost:9696 …` |

## Internal (Docker / not published)

| Port | Service            | Stack       | Notes |
|------|--------------------|-------------|-------|
| 8096 | Jellyfin           | jellyfin    | nginx proxies `:8443` → `jellyfin:8096` |
| 4533 | Navidrome          | navidrome   | nginx proxies `:8446` → `navidrome:4533` |
| 80   | Nextcloud          | nextcloud   | nginx proxies `:8444` → `nextcloud:80` |
| 80   | Pi-hole admin      | pihole      | nginx proxies `:8445` → `pihole` (`/admin`) |
| 80   | Vaultwarden        | vaultwarden | nginx proxies `:8447` → `vaultwarden:80` |
| 9980 | Collabora          | nextcloud   | nginx proxies `:8448` → `collabora:9980` |
| 3000 | Homepage           | homepage    | nginx proxies `:443` → `homepage:3000` |
| 5432 | Postgres           | nextcloud   | Nextcloud-only DB (`nextcloud-db`) on `nextcloud-internal` |
| 6379 | Redis              | nextcloud   | file locking / cache (`nextcloud-redis`) on `nextcloud-internal` |
| 8191 | FlareSolverr       | qbittorrent | Prowlarr reaches `http://127.0.0.1:8191` inside the VPN netns |

## Not published (optional)

| Port | Service     | Stack  | Notes |
|------|-------------|--------|-------|
| 53   | Pi-hole DNS | pihole | publish on the host only if this box is the LAN/Tailscale DNS resolver; can conflict with Tailscale MagicDNS |
| 6881 | BitTorrent  | qbittorrent | listen port inside Gluetun; actual forwarded port comes from the VPN |
