# Homelab

## llm

Local AI and MCP

### MCP Tools

#### Public

#### Private

## pihole

Pi-hole ad blocker — `https://lenovoflakes.tail62b305.ts.net:8445/admin/`

## nextcloud

Local Database, Nextcloud — `https://lenovoflakes.tail62b305.ts.net:8444/`

### Nextcloud dev log

`ssh -L 8501:localhost:8501 lenovo -N` 

[http://localhost:8501](http://localhost:8501)

## jellyfin

Jellyfin Media Container — `https://lenovoflakes.tail62b305.ts.net:8443/`

## qbittorrent

qBittorrent + Prowlarr + FlareSolverr behind Proton VPN (Gluetun)

## nginx

Reverse proxy (Tailscale TLS). Landing at `:443`; apps on `:8443` (Jellyfin), `:8444` (Nextcloud), `:8445` (Pi-hole).

## minecraft

Vanilla Minecraft server (`itzg/minecraft-server`) on port 25565.

```bash
cd minecraft && docker compose up -d
```

Join from the Minecraft client: `lenovoflakes.tail62b305.ts.net` (Tailscale). World data lives in `minecraft/mc-data/`.

## watchtower

Image updates (Watchtower) + git-sync (pull remote commits and recreate stacks).

```bash
cd src/watchtower
cp .env.example .env   # set HOMELAB_PATH to the host clone
docker compose up -d --build
```

Add `com.centurylinklabs.watchtower.enable=true` to any service whose image should auto-update. git-sync polls `origin`, fast-forward pulls, then runs `docker compose down` / `up -d` for every stack except watchtower itself.

Watchtower posts to ntfy on image updates; git-sync posts on `compose up` failures (and merge failures).

## ntfy

Self-hosted push notifications on port **2586** (auth off; Tailscale only). Default topic: `homelab`.

```bash
cd src/ntfy && docker compose up -d
```

- Server: `http://lenovoflakes.tail62b305.ts.net:2586`
- Subscribe (phone app): add that server, topic `homelab`
- Publish: `curl -d "hello" http://lenovoflakes.tail62b305.ts.net:2586/homelab`
