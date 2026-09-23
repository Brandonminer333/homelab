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

`git-sync` passes `storage.env` to every stack automatically. A bare
`docker compose up -d` does not, and fails with `required variable DATA_ROOT is
missing a value`. Use the wrapper instead — it adds the `--env-file` flags and
nothing else, so every compose subcommand works as usual:

```sh
./scripts/compose.sh src/qbittorrent up -d
./scripts/compose.sh src/nextcloud logs -f
```

It also works from inside a stack directory, where the path can be omitted:

```sh
cd src/qbittorrent && ../../scripts/compose.sh up -d
```

The equivalent raw command, if you would rather not use the wrapper, is
`docker compose --env-file <repo>/storage.env --env-file .env up -d`.
