# Collabora Online (LibreOffice)

LibreOffice-based document editors for WOPI clients (Seafile). Stateless — no database.

## First-time setup

Create `.env` on the **host** before setting `libreoffice.runs: true` in
[`config.yml`](../watchtower/config.yml). git-sync cannot start this stack
without it (`.env` is gitignored).

```bash
cd src/libreoffice
cp .env.example .env
# Set PASSWORD (openssl rand -base64 24)
# Confirm ALIASGROUP1 includes Seafile's public URL (:8444)
docker compose up -d
```

Or apply via git-sync after `.env` exists:

```bash
docker exec git-sync /bin/sh /homelab/src/watchtower/git-sync.sh sync
```

## Access

- Editors: `https://lenovoflakes.tail62b305.ts.net:8448/` (nginx → `libreoffice:9980`)
- Admin: `https://lenovoflakes.tail62b305.ts.net:8448/browser/dist/admin/admin.html`

## Seafile integration

Add to `/opt/seafile-data/conf/seahub_settings.py` on the host (see [`src/seafile/README.md`](../seafile/README.md)):

```python
OFFICE_SERVER_TYPE = 'CollaboraOffice'
OFFICE_WEB_APP_BASE_URL = 'https://lenovoflakes.tail62b305.ts.net:8448/hosting/discovery'
```

## Deploy verification

```bash
curl -k https://lenovoflakes.tail62b305.ts.net:8448/hosting/discovery
docker exec git-sync /bin/sh /homelab/src/watchtower/git-sync.sh plan
docker exec git-sync /bin/sh /homelab/src/watchtower/git-sync.sh sync
```

After migrating from ONLYOFFICE on the host:

```bash
# Stop old stack if still running
docker rm -f onlyoffice 2>/dev/null || true
# Optional: remove old data
# rm -rf data/onlyoffice
```
