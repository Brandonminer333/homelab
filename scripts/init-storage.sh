#!/bin/sh
# Create the on-HDD directory tree that the compose stacks bind-mount.
#
# Docker creates a missing bind source as root:root. Jellyfin, Navidrome,
# qBittorrent and Prowlarr all run as PUID:PGID and cannot write their own
# databases into a root-owned directory — Navidrome fails with "unable to open
# database file" in a restart loop. This script pre-creates every path with the
# right owner, replacing the .gitkeep files that used to do it from git.
#
# Run on a fresh host before the first `docker compose up`, and again after
# changing any path in storage.env:
#
#   sudo ./scripts/init-storage.sh
#
# Idempotent. Trees whose entrypoints chown themselves (Nextcloud, Postgres,
# Vaultwarden, ntfy, Pi-hole, Gluetun) are created but left to root.
set -eu

cd "$(dirname "$0")/.."

if [ ! -f storage.env ]; then
  echo "ERROR: storage.env not found in $(pwd)" >&2
  exit 1
fi
. ./storage.env

: "${DATA_ROOT:?Set DATA_ROOT in storage.env}"
: "${MEDIA_ROOT:?Set MEDIA_ROOT in storage.env}"

# PUID/PGID from the environment, else the user behind sudo, else the caller.
# Must match the PUID/PGID in src/media/*/.env and src/qbittorrent/.env.
uid="${PUID:-${SUDO_UID:-$(id -u)}}"
gid="${PGID:-${SUDO_GID:-$(id -g)}}"

# A path that exists but is not a mount point usually means the disk failed to
# mount and the data would silently land on the system SSD.
if command -v findmnt >/dev/null 2>&1; then
  if ! findmnt -rno TARGET "$DATA_ROOT" >/dev/null 2>&1; then
    echo "WARN: $DATA_ROOT is not a mount point — check /etc/fstab before continuing" >&2
  fi
fi

# Created as root; each image's entrypoint fixes ownership itself.
root_owned="
nextcloud/html
nextcloud/data
nextcloud/db
vaultwarden
kitchenowl
pihole/etc-pihole
pihole/etc-dnsmasq.d
ntfy/cache
gluetun
"

# Containers here run as PUID:PGID and must own these outright.
user_owned="
jellyfin/config
jellyfin/cache
navidrome/metadata
qbittorrent/config
qbittorrent/downloads
prowlarr/config
"

for rel in $root_owned; do
  mkdir -p "${DATA_ROOT}/${rel}"
done

for rel in $user_owned; do
  mkdir -p "${DATA_ROOT}/${rel}"
  chown "${uid}:${gid}" "${DATA_ROOT}/${rel}"
done

# MEDIA_ROOT may point at a different disk than DATA_ROOT.
for rel in videos music; do
  mkdir -p "${MEDIA_ROOT}/${rel}"
  chown "${uid}:${gid}" "${MEDIA_ROOT}/${rel}"
done

echo "storage ready: DATA_ROOT=${DATA_ROOT} MEDIA_ROOT=${MEDIA_ROOT} owner=${uid}:${gid}"
