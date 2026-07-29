# Shared MariaDB

One MariaDB container on the `homelab` Docker network. Isolated databases/users:

| Database     | User         | Used by                          |
|--------------|--------------|----------------------------------|
| `nextcloud`  | `nextcloud`  | [`src/nextcloud`](../nextcloud/) |
| `forgejo`    | `forgejo`    | [`src/forgejo`](../forgejo/)     |
| `onlyoffice` | `onlyoffice` | [`src/onlyoffice`](../onlyoffice/) |

Hostname from other containers: `mariadb:3306` (not published on the host).

## First-time setup

```bash
cp .env.example .env
# Set MARIADB_ROOT_PASSWORD and each *_DB_PASSWORD (e.g. openssl rand -base64 32)
# Copy NEXTCLOUD_DB_PASSWORD / FORGEJO_DB_PASSWORD / ONLYOFFICE_DB_PASSWORD
# into the matching app .env files (values must match).

cd src/mariadb && docker compose up -d
docker exec -it mariadb mariadb -u root -p -e 'SHOW DATABASES;'
docker exec -it mariadb mariadb -u root -p -e 'SELECT User, Host FROM mysql.user;'
```

Init scripts under `./init` run **only** on first cluster init (empty datadir). To re-bootstrap users/DBs: stop the stack, wipe `./data` (keep `.gitkeep`), start again.

## Start order

1. `src/mariadb` (healthy)
2. Nextcloud / Forgejo / ONLYOFFICE stacks

## Isolation check (optional)

```bash
docker exec -it mariadb mariadb -u nextcloud -p -e 'USE forgejo;'
# should fail (no privileges on forgejo for user nextcloud)
```
