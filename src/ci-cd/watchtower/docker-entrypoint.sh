#!/bin/sh
# Run bind-mounted git-sync.sh when present so pulls update logic without rebuild.
set -eu
REPO_DIR="${REPO_DIR:-/homelab}"
MOUNTED="${REPO_DIR}/src/watchtower/git-sync.sh"
if [ -f "$MOUNTED" ]; then
  exec /bin/sh "$MOUNTED"
fi
exec /bin/sh /usr/local/bin/git-sync.sh
