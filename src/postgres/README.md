# Shared PostgreSQL

One Postgres 16 container on the `homelab` Docker network. Isolated databases/roles:

| Database     | Role         | Used by                          |
|--------------|--------------|----------------------------------|
| `nextcloud`  | `nextcloud`  | [`src/nextcloud`](../nextcloud/) |
| `forgejo`    | `forgejo`    | [`src/forgejo`](../forgejo/)     |
| `onlyoffice` | `onlyoffice` | [`src/onlyoffice`](../onlyoffice/) |

Hostname from other containers: `postgres:5432` (not published on the host).

## First-time setup

```bash
cp .env.example .env
# Set POSTGRES_PASSWORD and each *_DB_PASSWORD (e.g. openssl rand -base64 32)
# Copy NEXTCLOUD_DB_PASSWORD / FORGEJO_DB_PASSWORD / ONLYOFFICE_DB_PASSWORD
# into the matching app .env files (values must match).

cd src/postgres && docker compose up -d
docker exec -it postgres psql -U postgres -c '\l'
docker exec -it postgres psql -U postgres -c '\du'
```

Init scripts under `./init` run **only** when `./data` is empty (first cluster init). To re-bootstrap roles/DBs: stop the stack, wipe `./data` (keep `.gitkeep`), start again.

## Start order

1. `src/postgres` (healthy)
2. Nextcloud / Forgejo / ONLYOFFICE stacks

## Deploy notes (host)

### Nextcloud (fresh Postgres; no MariaDB migration)

1. Stop Nextcloud + old MariaDB.
2. Delete `/opt/nextcloud/db`.
3. Reset Nextcloud install config so env-driven first boot can create schema on Postgres (clear or re-init `/opt/nextcloud/html` config; treat as a new install).
4. Ensure `NEXTCLOUD_DB_PASSWORD` matches `src/postgres/.env`, then `docker compose up -d` in `src/nextcloud`.

### Forgejo (optional dump/restore)

To keep existing metadata:

1. Stop Forgejo while old `forgejo-db` is still up.
2. `docker exec forgejo-db pg_dump -U forgejo forgejo > forgejo.dump.sql`
3. Bring up shared Postgres; restore into the `forgejo` DB as role `forgejo`.
4. Stop/remove `forgejo-db`; start Forgejo with `HOST=postgres:5432`.
5. Archive then delete old `src/forgejo/postgres` after verifying.

Or skip the dump and accept a fresh Forgejo DB / first-run setup.

### ONLYOFFICE

1. Stop the stack; ensure `ONLYOFFICE_DB_PASSWORD` matches postgres `.env`.
2. Start after Postgres is healthy (DB must already exist; Document Server creates tables).
3. Archive/remove `src/onlyoffice/db` once confirmed (embedded Postgres unused).
4. Keep `JWT_SECRET` stable so the Nextcloud connector still works.

### Isolation check (optional)

```bash
docker exec -it postgres psql -U nextcloud -d forgejo
# should fail (no CONNECT on forgejo for role nextcloud)
```
