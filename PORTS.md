# Homelab ports

Hostname: `lenovoflakes.tail62b305.ts.net` (Tailscale MagicDNS).

## Public (Tailscale / host-published)

| Port  | Service              | Stack       | Access |
|-------|----------------------|-------------|--------|
| 80    | HTTP → HTTPS         | nginx       | redirect to `:443` |
| 443   | Homepage             | nginx → homepage | `https://lenovoflakes.tail62b305.ts.net/` |
| 8443  | Jellyfin             | nginx → jellyfin | `https://lenovoflakes.tail62b305.ts.net:8443/` |
| 8444  | Seafile              | nginx → seafile | `https://lenovoflakes.tail62b305.ts.net:8444/` |
| 8445  | Pi-hole admin        | nginx → pihole | `https://lenovoflakes.tail62b305.ts.net:8445/admin/` |
| 8447  | Vaultwarden          | nginx → vaultwarden | `https://lenovoflakes.tail62b305.ts.net:8447/` |
| 8448  | Collabora (LibreOffice) | nginx → libreoffice | `https://lenovoflakes.tail62b305.ts.net:8448/` |
| 8450  | Radicale             | nginx → radicale | `https://lenovoflakes.tail62b305.ts.net:8450/` |
| 2586  | ntfy                 | ntfy        | `http://lenovoflakes.tail62b305.ts.net:2586` |

## Localhost-only (SSH tunnel)

| Port | Service       | Stack       | Notes |
|------|---------------|-------------|-------|
| 8080 | qBittorrent   | qbittorrent | behind Gluetun; `ssh -L 8080:localhost:8080 …` |
| 9696 | Prowlarr      | qbittorrent | behind Gluetun; `ssh -L 9696:localhost:9696 …` |

## Internal (Docker / not published)

| Port | Service            | Stack       | Notes |
|------|--------------------|-------------|-------|
| 8096 | Jellyfin           | jellyfin    | nginx proxies `:8443` → `jellyfin:8096` |
| 80   | Seafile            | seafile     | nginx proxies `:8444` → `seafile:80` |
| 80   | Pi-hole admin      | pihole      | nginx proxies `:8445` → `pihole` (`/admin`) |
| 80   | Vaultwarden        | vaultwarden | nginx proxies `:8447` → `vaultwarden:80` |
| 9980 | Collabora (LibreOffice) | libreoffice | nginx proxies `:8448` → `libreoffice:9980` |
| 5232 | Radicale           | radicale    | nginx proxies `:8450` → `radicale:5232` |
| 3000 | Homepage           | homepage    | nginx proxies `:443` → `homepage:3000` |
| 3306 | MariaDB            | seafile     | Seafile-only DB (`seafile-db`); hostname `db` on `seafile-internal` |
| 8191 | FlareSolverr       | qbittorrent | Prowlarr reaches `http://127.0.0.1:8191` inside the VPN netns |

## Not published (optional)

| Port | Service     | Stack  | Notes |
|------|-------------|--------|-------|
| 53   | Pi-hole DNS | pihole | publish on the host only if this box is the LAN/Tailscale DNS resolver; can conflict with Tailscale MagicDNS |
| 6881 | BitTorrent  | qbittorrent | listen port inside Gluetun; actual forwarded port comes from the VPN |
