#!/bin/sh
# Poll origin for new commits; on change, git pull and sync compose stacks to
# config/config.yml (start / stop / restart). Never tear down this watchtower
# stack mid-deploy.
set -eu

REPO_DIR="${REPO_DIR:-/homelab}"
BRANCH="${GIT_BRANCH:-main}"
INTERVAL="${POLL_INTERVAL:-300}"
CONFIG_FILE="${CONFIG_FILE:-${REPO_DIR}/config/config.yml}"
NTFY_URL="${NTFY_URL:-http://ntfy/homelab}"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2
}

# Best-effort notify; never fail the deploy loop if ntfy is down.
# Usage: notify TITLE MESSAGE [PRIORITY] [TAGS]
notify() {
  title="$1"
  message="$2"
  priority="${3:-default}"
  tags="${4:-warning}"
  curl -fsS \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -H "Tags: ${tags}" \
    -d "${message}" \
    "${NTFY_URL}" >/dev/null 2>&1 || log "WARN: ntfy notify failed"
}

# Format a space-separated list as comma-separated, or "none".
fmt_list() {
  list="$(echo "$1" | xargs)"
  if [ -z "$list" ]; then
    echo "none"
  else
    echo "$list" | tr ' ' ','
  fi
}

# Map config key → compose directory relative to REPO_DIR.
stack_dir() {
  name="$1"
  path="$(yq -r ".containers[\"${name}\"].path // \"\"" "$CONFIG_FILE" 2>/dev/null || true)"
  if [ -n "$path" ] && [ "$path" != "null" ]; then
    echo "$path"
    return
  fi
  echo "src/${name}"
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

# True if any container in the compose project is running.
stack_running() {
  dir="$1"
  file="$(compose_file "$dir")" || return 1
  ids="$(docker compose -f "$file" --project-directory "${REPO_DIR}/${dir}" ps -q --status running 2>/dev/null || true)"
  [ -n "$ids" ]
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

# Recreate running stack so bind-mounted compose/config changes take effect.
compose_restart() {
  dir="$1"
  file="$(compose_file "$dir")" || {
    log "WARN: no compose file in $dir"
    return 1
  }
  log "restart $dir"
  docker compose -f "$file" --project-directory "${REPO_DIR}/${dir}" up -d --force-recreate
}

run_enabled() {
  name="$1"
  val="$(yq -r ".containers[\"${name}\"].run" "$CONFIG_FILE")"
  case "$val" in
    true|True|TRUE|yes|Yes|YES|1) return 0 ;;
    *) return 1 ;;
  esac
}

# Space-separated dependency names for a stack (may be empty).
stack_deps() {
  name="$1"
  yq -r ".containers[\"${name}\"].\"depends-on\" // [] | .[]" "$CONFIG_FILE" 2>/dev/null | tr '\n' ' '
}

all_stack_names() {
  yq -r '.containers | keys | .[]' "$CONFIG_FILE"
}

# Sort for tear-down: nginx first, then everything else (deps after dependents).
order_down() {
  nginx=""
  rest=""
  for s in $1; do
    case "$s" in
      nginx) nginx="$nginx $s" ;;
      *) rest="$rest $s" ;;
    esac
  done
  echo "$nginx $rest" | xargs
}

# Topological order for start: respect depends-on; nginx always last.
# Prints names one per line; exits 1 if a cycle or missing enabled dep is found.
order_up() {
  remaining="$1"
  started=""
  # nginx deferred to the end
  has_nginx=0
  trimmed=""
  for s in $remaining; do
    if [ "$s" = "nginx" ]; then
      has_nginx=1
    else
      trimmed="$trimmed $s"
    fi
  done
  remaining="$(echo "$trimmed" | xargs)"

  # Safety: at most N passes for N stacks
  n=0
  for _ in $remaining; do n=$((n + 1)); done
  n=$((n + 2))

  while [ -n "$remaining" ] && [ "$n" -gt 0 ]; do
    n=$((n - 1))
    progress=0
    next_remaining=""
    for s in $remaining; do
      ready=1
      for dep in $(stack_deps "$s"); do
        # Dependency must be enabled and already ordered, or we cannot start.
        if ! run_enabled "$dep"; then
          log "ERROR: $s depends on $dep but $dep.run is false"
          return 1
        fi
        case " $started " in
          *" $dep "*) ;;
          *) ready=0; break ;;
        esac
      done
      if [ "$ready" -eq 1 ]; then
        echo "$s"
        started="$started $s"
        progress=1
      else
        next_remaining="$next_remaining $s"
      fi
    done
    remaining="$(echo "$next_remaining" | xargs)"
    if [ "$progress" -eq 0 ] && [ -n "$remaining" ]; then
      log "ERROR: dependency cycle or unsatisfied depends-on among:$remaining"
      return 1
    fi
  done

  if [ "$has_nginx" -eq 1 ]; then
    echo "nginx"
  fi
}

sync_from_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: config not found at $CONFIG_FILE"
    notify "Homelab deploy failed" "missing ${CONFIG_FILE}" high
    return 1
  fi

  if ! command -v yq >/dev/null 2>&1; then
    log "ERROR: yq is required to parse $CONFIG_FILE"
    notify "Homelab deploy failed" "yq not installed in git-sync image" high
    return 1
  fi

  log "Syncing stacks from $CONFIG_FILE"

  to_stop=""
  to_start=""
  for name in $(all_stack_names); do
    # Never manage ourselves from inside the watchtower stack.
    if [ "$name" = "watchtower" ]; then
      log "skip  watchtower (self)"
      continue
    fi

    dir="$(stack_dir "$name")"
    if ! compose_file "$dir" >/dev/null; then
      if run_enabled "$name"; then
        log "WARN: $name.run is true but no compose file in $dir — skipping"
      fi
      continue
    fi

    if run_enabled "$name"; then
      to_start="$to_start $name"
    else
      to_stop="$to_stop $name"
    fi
  done

  ordered=""
  if ! ordered="$(order_up "$to_start")"; then
    notify "Homelab deploy failed" "dependency ordering failed; see git-sync logs" high
    return 1
  fi

  # Classify enabled stacks before acting (for the single lag advisory notify).
  starting=""
  restarting=""
  for name in $ordered; do
    dir="$(stack_dir "$name")"
    if stack_running "$dir" 2>/dev/null; then
      restarting="${restarting} ${name}"
    else
      starting="${starting} ${name}"
    fi
  done

  # One notification per detected update: where downtime / lag will be.
  notify \
    "Homelab update detected" \
    "starting: $(fmt_list "$starting")
restarting: $(fmt_list "$restarting")" \
    default \
    whale

  failed=""

  for name in $(order_down "$to_stop"); do
    dir="$(stack_dir "$name")"
    if stack_running "$dir" 2>/dev/null; then
      compose_down "$dir" || {
        log "WARN: down failed for $name"
        failed="${failed} down:${name}"
      }
    else
      log "skip  $name (already stopped)"
    fi
  done

  for name in $ordered; do
    dir="$(stack_dir "$name")"
    case " ${restarting} " in
      *" ${name} "*)
        if ! compose_restart "$dir"; then
          log "ERROR: restart failed for $name"
          failed="${failed} restart:${name}"
        fi
        ;;
      *)
        if ! compose_up "$dir"; then
          log "ERROR: up failed for $name"
          failed="${failed} up:${name}"
        fi
        ;;
    esac
  done

  if [ -n "$failed" ]; then
    notify "Homelab deploy failed" "compose failed for:${failed}" high
    return 1
  fi

  log "Sync finished"
}

# Bind-mounted repos often fail ownership checks when the container runs as root.
git config --global --add safe.directory "$REPO_DIR"

cd "$REPO_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "ERROR: $REPO_DIR is not a git repository"
  exit 1
fi

log "Watching $REPO_DIR branch=$BRANCH interval=${INTERVAL}s config=$CONFIG_FILE"

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
      sync_from_config || log "WARN: sync_from_config returned non-zero"
    else
      log "ERROR: fast-forward merge failed (local divergence?). Skipping sync."
      notify "Homelab git-sync failed" "fast-forward merge failed on ${BRANCH}; sync skipped" high
    fi
  else
    log "Up to date at ${LOCAL}"
  fi

  sleep "$INTERVAL"
done
