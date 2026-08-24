# Seafile Homelab Setup

Community Edition via `seafileltd/seafile-mc:12.0-latest`.

Database: shared MariaDB (`src/mariadb`), user `seafile`, DBs `ccnet_db` / `seafile_db` / `seahub_db`. Bring MariaDB up first.

Memcached runs beside Seafile on a private compose network (`seafile-internal`); only Seafile joins the shared `homelab` network for MariaDB + nginx.

## First-time setup

```bash
cp .env.example .env
# SEAFILE_DB_PASSWORD — same as src/mariadb/.env
# INIT_SEAFILE_MYSQL_ROOT_PASSWORD — same as MARIADB_ROOT_PASSWORD
# JWT_PRIVATE_KEY — pwgen -s 40 1
# INIT_SEAFILE_ADMIN_EMAIL / INIT_SEAFILE_ADMIN_PASSWORD

# MariaDB must already be healthy with the three Seafile DBs created:
cd ../mariadb && docker compose up -d

cd ../seafile && docker compose up -d
```

Data volume: `/opt/seafile-data` on the host → `/shared` in the container.

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
