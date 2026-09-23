# Homelab

## Sevices

| Service | Software |
| Media Server | jellyfin |
| Music Server | Navidrome |
| File Drive / Calendar / Contacts | Nextcloud |
| Notification Server | nfty |
| DNS | pihole
| Torrenting | qbittorrent |
| Git Sync | watchtower |
| Password Manager | vaultwarden |
| Document Editors | Collabora (via Nextcloud) |
| Dashboard | homepage |

## Storage

Persistent data lives outside this repo, on the 1 TB HDD. The location is
declared once in [`storage.env`](storage.env):

| Variable | Default | Holds |
| --- | --- | --- |
| `DATA_ROOT` | `/mnt/homelab-data` | databases, service config, downloads |
| `MEDIA_ROOT` | `/mnt/homelab-data/media` | video and music libraries (mounted read-only) |

Every compose file references `${DATA_ROOT}` / `${MEDIA_ROOT}` instead of a
relative path, so moving to a different disk is a one-line edit followed by an
`rsync` and a restart.

On a fresh host, create the directory tree before the first start — Docker would
otherwise create the missing paths as `root:root`, which breaks the containers
that run as `PUID:PGID`:

```sh
sudo ./scripts/init-storage.sh
```

`git-sync` passes `storage.env` to every stack automatically. Running compose by
hand needs it as an extra `--env-file`; the `Start:` comment at the top of each
compose file has the exact command, for example:

```sh
cd src/nextcloud && docker compose --env-file ../../storage.env --env-file .env up -d
```
