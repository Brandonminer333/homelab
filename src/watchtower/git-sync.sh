#!/bin/sh
# Poll origin for new commits; on change, git pull and recreate every compose stack
# except this watchtower stack (so we do not tear down ourselves mid-deploy).
set -eu

REPO_DIR="${REPO_DIR:-/homelab}"
BRANCH="${GIT_BRANCH:-main}"
INTERVAL="${POLL_INTERVAL:-300}"
# Space-separated paths relative to REPO_DIR. Empty = auto-discover.
# Order matters: apps first, nginx last (so upstreams exist when nginx starts).
STACKS="${STACKS:-}"
NTFY_URL="${NTFY_URL:-http://ntfy/homelab}"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

# Best-effort notify; never fail the deploy loop if ntfy is down.
notify() {
  title="$1"
  message="$2"
  priority="${3:-default}"
  curl -fsS \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -H "Tags: warning" \
    -d "${message}" \
    "${NTFY_URL}" >/dev/null 2>&1 || log "WARN: ntfy notify failed"
}

discover_stacks() {
  find "$REPO_DIR" \
    -type f \
    \( -name 'docker-compose.yml' -o -name 'compose.yml' \) \
    ! -path '*/watchtower/*' \
    ! -path '*/.git/*' \
    | sed "s|^${REPO_DIR}/||; s|/[^/]*$||" \
    | sort -u
}

# Prefer nginx last on up; reverse for down.
order_stacks_up() {
  apps=""
  nginx=""
  for s in $1; do
    case "$s" in
      */nginx|nginx) nginx="$nginx $s" ;;
      *) apps="$apps $s" ;;
    esac
  done
  echo "$apps $nginx" | xargs
}

order_stacks_down() {
  apps=""
  nginx=""
  for s in $1; do
    case "$s" in
      */nginx|nginx) nginx="$nginx $s" ;;
      *) apps="$apps $s" ;;
    esac
  done
  # nginx first on tear-down
  echo "$nginx $apps" | xargs
}

compose_file() {
  dir="$1"
  if [ -f "${REPO_DIR}/${dir}/docker-compose.yml" ]; then
    echo "${REPO_DIR}/${dir}/docker-compose.yml"
  elif [ -f "${REPO_DIR}/${dir}/compose.yml" ]; then
    echo "${REPO_DIR}/${dir}/compose.yml"
  else
    return 1
  fi
}

compose_down() {
  dir="$1"
  file="$(compose_file "$dir")" || {
    log "WARN: no compose file in $dir"
    return 1
  }
  log "down  $dir"
  docker compose -f "$file" --project-directory "${REPO_DIR}/${dir}" down
}

compose_up() {
  dir="$1"
  file="$(compose_file "$dir")" || {
    log "WARN: no compose file in $dir"
    return 1
  }
  log "up    $dir"
  docker compose -f "$file" --project-directory "${REPO_DIR}/${dir}" up -d
}

redeploy_all() {
  if [ -z "$STACKS" ]; then
    STACKS="$(discover_stacks)"
  fi
  log "Redeploying stacks:$STACKS"

  for dir in $(order_stacks_down "$STACKS"); do
    compose_down "$dir" || log "WARN: down failed for $dir (continuing)"
  done

  failed=""
  for dir in $(order_stacks_up "$STACKS"); do
    if ! compose_up "$dir"; then
      log "ERROR: up failed for $dir"
      failed="${failed} ${dir}"
    fi
  done

  if [ -n "$failed" ]; then
    notify "Homelab deploy failed" "compose up failed for:${failed}" high
  fi

  log "Redeploy finished"
}

# Bind-mounted repos often fail ownership checks when the container runs as root.
git config --global --add safe.directory "$REPO_DIR"

cd "$REPO_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "ERROR: $REPO_DIR is not a git repository"
  exit 1
fi

log "Watching $REPO_DIR branch=$BRANCH interval=${INTERVAL}s"

while true; do
  if ! git fetch origin "$BRANCH"; then
    log "WARN: git fetch failed; retrying in ${INTERVAL}s"
    sleep "$INTERVAL"
    continue
  fi

  LOCAL="$(git rev-parse HEAD)"
  REMOTE="$(git rev-parse "origin/${BRANCH}")"

  if [ "$LOCAL" != "$REMOTE" ]; then
    log "Update detected: ${LOCAL} -> ${REMOTE}"
    if git merge --ff-only "origin/${BRANCH}"; then
      redeploy_all
    else
      log "ERROR: fast-forward merge failed (local divergence?). Skipping redeploy."
      notify "Homelab git-sync failed" "fast-forward merge failed on ${BRANCH}; redeploy skipped" high
    fi
  else
    log "Up to date at ${LOCAL}"
  fi

  sleep "$INTERVAL"
done
