# Shared MariaDB

One MariaDB container on the `homelab` Docker network. Isolated databases/users:

| Database(s)                          | User         | Used by                            |
|--------------------------------------|--------------|------------------------------------|
| `ccnet_db`, `seafile_db`, `seahub_db` | `seafile`    | [`src/seafile`](../seafile/)       |
| `forgejo`                            | `forgejo`    | [`src/forgejo`](../forgejo/)       |

Hostname from other containers: `mariadb:3306` (not published on the host).

## First-time setup

```bash
cp .env.example .env
# Set MARIADB_ROOT_PASSWORD and each *_DB_PASSWORD (e.g. openssl rand -base64 32)
# Copy SEAFILE_DB_PASSWORD / FORGEJO_DB_PASSWORD
# into the matching app .env files (values must match).

cd src/mariadb && docker compose up -d
docker exec -it mariadb mariadb -u root -p -e 'SHOW DATABASES;'
docker exec -it mariadb mariadb -u root -p -e 'SELECT User, Host FROM mysql.user;'
```

Init scripts under `./init` run **only** on first cluster init (empty datadir). To re-bootstrap users/DBs: stop the stack, wipe `../../data/mariadb` (keep `.gitkeep`), start again.

## Start order

1. `src/mariadb` (healthy)
2. Seafile / Forgejo stacks

## Isolation check (optional)

```bash
docker exec -it mariadb mariadb -u seafile -p -e 'USE forgejo;'
# should fail (no privileges on forgejo for user seafile)
```
