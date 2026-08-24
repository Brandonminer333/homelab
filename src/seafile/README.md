# Seafile Homelab Setup

Community Edition via `seafileltd/seafile-mc:12.0-latest`.

Database: dedicated MariaDB in this stack (`seafile-db`), user `seafile`, DBs `ccnet_db` / `seafile_db` / `seahub_db`. MariaDB and memcached stay on a private compose network (`seafile-internal`); only Seafile joins the shared `homelab` network for nginx.

## First-time setup

```bash
cp .env.example .env
# MARIADB_ROOT_PASSWORD / SEAFILE_DB_PASSWORD — openssl rand -base64 32
# JWT_PRIVATE_KEY — pwgen -s 40 1
# INIT_SEAFILE_ADMIN_EMAIL / INIT_SEAFILE_ADMIN_PASSWORD

cd src/seafile && docker compose up -d
```

Data volumes:

| Host | Container | Notes |
|------|-----------|-------|
| `/opt/seafile-data` | `/shared` | Seafile config + libraries |
| `../../data/seafile/mariadb` | `/var/lib/mysql` | This stack's MariaDB only |

If Seafile was already initialized against the old shared `mariadb` hostname, update `DB_HOST` in `/opt/seafile-data/conf/` to `db` (or restore that datadir into `../../data/seafile/mariadb`). Env vars apply on first boot only.

## Access

`https://lenovoflakes.tail62b305.ts.net:8444/` (nginx → `seafile:80`)

## Document editing (Collabora)

In-browser editing uses Collabora Online (`src/libreoffice`). Add to the Seafile config on the host volume:

```bash
# /opt/seafile-data/conf/seahub_settings.py
OFFICE_SERVER_TYPE = 'CollaboraOffice'
OFFICE_WEB_APP_BASE_URL = 'https://lenovoflakes.tail62b305.ts.net:8448/hosting/discovery'
```

Restart Seafile after editing:

```bash
cd src/seafile && docker compose restart
```

Verify discovery: `curl -k https://lenovoflakes.tail62b305.ts.net:8448/hosting/discovery`
