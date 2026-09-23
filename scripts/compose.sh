#!/bin/sh
# docker compose for a homelab stack, with storage.env already applied.
#
# Bind mounts resolve through DATA_ROOT / MEDIA_ROOT from storage.env at the repo
# root, so a bare `docker compose up -d` fails with "required variable DATA_ROOT
# is missing a value". This wrapper adds the --env-file flags that git-sync
# passes on a real deploy, so manual starts behave the same way.
#
# Usage, from anywhere:
#   scripts/compose.sh src/qbittorrent up -d
# Or from inside the stack directory:
#   cd src/qbittorrent && ../../scripts/compose.sh up -d
#
# Any docker compose subcommand works: up, down, logs -f, ps, pull, config.
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
storage_env="${repo_root}/storage.env"

if [ ! -f "$storage_env" ]; then
  echo "ERROR: $storage_env not found" >&2
  exit 1
fi

# A leading argument naming a stack directory wins; otherwise use the current
# directory. Resolved against both the caller's cwd and the repo root so
# `src/qbittorrent` works from anywhere.
stack=""
if [ "$#" -gt 0 ]; then
  for base in "$PWD" "$repo_root"; do
    if [ -f "${base}/$1/docker-compose.yml" ]; then
      stack="$(CDPATH= cd -- "${base}/$1" && pwd)"
      shift
      break
    fi
  done
fi

if [ -z "$stack" ] && [ -f "${PWD}/docker-compose.yml" ]; then
  stack="$PWD"
fi

if [ -z "$stack" ]; then
  echo "usage: $0 [STACK_DIR] COMMAND [ARGS...]" >&2
  echo "       no docker-compose.yml in the current directory, and" >&2
  echo "       '${1:-}' is not a stack directory" >&2
  exit 1
fi

# --project-directory keeps the project name equal to the stack directory name,
# matching the containers git-sync creates. Stack .env goes last: later wins.
if [ -f "${stack}/.env" ]; then
  exec docker compose --project-directory "$stack" -f "${stack}/docker-compose.yml" \
    --env-file "$storage_env" --env-file "${stack}/.env" "$@"
else
  exec docker compose --project-directory "$stack" -f "${stack}/docker-compose.yml" \
    --env-file "$storage_env" "$@"
fi
