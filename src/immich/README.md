# Immich Homelab Setup

Photo library via Immich `v3` with the **bundled** Postgres (vectorchord image) and Valkey. Redis/Postgres stay on a private `immich-internal` network; only the Immich API container joins `homelab` for nginx.

## Prerequisites

1. Seafile desktop client on the Docker host syncing the **Photos** library to:
   `/home/branflakes/Seafile/Photos`
   (override with `EXTERNAL_LIBRARY_PATH` in `.env` if different)
2. Shared `homelab` Docker network already exists
3. Do **not** mount `/opt/seafile-data` — that is Seafile block storage and is not a browsable photo tree

## First-time setup

```bash
cp .env.example .env
# Set DB_PASSWORD (pwgen -s 32 1) and confirm EXTERNAL_LIBRARY_PATH

mkdir -p ../../data/immich/library ../../data/immich/postgres
cd src/immich && docker compose up -d
```

Reload nginx after adding `:8449` (see `src/nginx`).

## Wire Seafile Photos into Immich

1. Open `https://lenovoflakes.tail62b305.ts.net:8449/` and create the admin account
2. **Administration → Libraries → Create external library**
3. Import path: `/mnt/seafile-photos` (container path for the Seafile sync mount)
4. Assign to your user → **Scan**

Immich indexes in place (read-only); originals stay in the Seafile sync folder. New photos appear after Seafile syncs and Immich rescans (or on the library’s scan interval).

## Access

`https://lenovoflakes.tail62b305.ts.net:8449/` (nginx → `immich:2283`)

## Layout

| Host | Container | Notes |
|------|-----------|--------|
| `../../data/immich/library` | `/data` | Immich-managed uploads / derived assets |
| `../../data/immich/postgres` | Postgres data | Bundled Immich DB only |
| `EXTERNAL_LIBRARY_PATH` | `/mnt/seafile-photos` (ro) | Seafile-synced Photos |
