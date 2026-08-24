#!/bin/sh
# Poll origin for new commits; on change, git pull and sync compose stacks to
# src/watchtower/config.yml (start / stop / apply compose changes). Never tear
# down this watchtower stack mid-deploy.
#
# Sync phases:
#   1. Stop every stack with runs:false (lowest priority first)
#   2. Apply compose up -d for runs:true stacks (highest priority first;
#      depends-on still enforced). Compose recreates only when the spec changed.
#
# On compose failure for one stack: ntfy that stack, then continue others.
#
# This script is executed from the bind-mounted repo so git pulls pick up
# logic changes without rebuilding the image.
set -eu

REPO_DIR="${REPO_DIR:-/homelab}"
BRANCH="${GIT_BRANCH:-main}"
INTERVAL="${POLL_INTERVAL:-300}"
# Desired stack state is always the public YAML in-repo (not .env).
CONFIG_FILE="${REPO_DIR}/src/watchtower/config.yml"
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

# Sorted container IDs for a stack (one line, space-separated).
stack_container_ids() {
  dir="$1"
  file="$(compose_file "$dir")" || return 1
  docker compose -f "$file" --project-directory "${REPO_DIR}/${dir}" ps -q 2>/dev/null \
    | sort | tr '\n' ' '
}

# Apply compose up -d. On success prints one of: started, recreated, unchanged.
compose_up() {
  dir="$1"
  file="$(compose_file "$dir")" || {
    log "WARN: no compose file in $dir"
    return 1
  }

  was_running=0
  before_ids=""
  if stack_running "$dir"; then
    was_running=1
    before_ids="$(stack_container_ids "$dir" || true)"
  fi

  log "up    $dir"
  if ! docker compose -f "$file" --project-directory "${REPO_DIR}/${dir}" up -d 1>&2; then
    return 1
  fi

  if [ "$was_running" -eq 0 ]; then
    echo started
    return 0
  fi

  after_ids="$(stack_container_ids "$dir" || true)"
  if [ "$before_ids" != "$after_ids" ]; then
    echo recreated
  else
    echo unchanged
  fi
}

# Notify about a single stack failure, then caller continues.
notify_stack_failed() {
  action="$1"
  name="$2"
  log "ERROR: ${action} failed for ${name} — continuing"
  notify \
    "Homelab ${action} failed" \
    "${name} failed during ${action}; continuing with remaining stacks" \
    high \
    warning
}

# Integer priority from config (default 0). Higher = earlier on up.
stack_priority() {
  name="$1"
  pri="$(yq -r ".containers[\"${name}\"].priority // 0" "$CONFIG_FILE" 2>/dev/null || echo 0)"
  case "$pri" in
    ''|null) echo 0 ;;
    *) echo "$pri" ;;
  esac
}

# Normalize runs to lowercase string (config key is `runs`).
runs_is_true() {
  name="$1"
  val="$(yq -r ".containers[\"${name}\"].runs | tostring | downcase" "$CONFIG_FILE" 2>/dev/null || echo false)"
  [ "$val" = "true" ]
}

# Space-separated dependency names for a stack (may be empty).
stack_deps() {
  name="$1"
  yq -r ".containers[\"${name}\"].\"depends-on\" // [] | .[]" "$CONFIG_FILE" 2>/dev/null | tr '\n' ' '
}

# Names with runs true (one per line), excluding watchtower.
enabled_stack_names() {
  yq -r '
    .containers
    | to_entries[]
    | select(.key != "watchtower")
    | select((.value.runs | tostring | downcase) == "true")
    | .key
  ' "$CONFIG_FILE"
}

# Names with runs not true (one per line), excluding watchtower.
disabled_stack_names() {
  yq -r '
    .containers
    | to_entries[]
    | select(.key != "watchtower")
    | select((.value.runs | tostring | downcase) != "true")
    | .key
  ' "$CONFIG_FILE"
}

# Tear-down order: lowest priority first. Prints names one per line.
order_down() {
  remaining="$1"
  [ -z "$(echo "$remaining" | xargs)" ] && return 0

  lines=""
  for s in $remaining; do
    lines="${lines}$(stack_priority "$s") ${s}
"
  done
  echo "$lines" | sed '/^$/d' | sort -n -k1,1 -k2,2 | awk '{print $2}'
}

# Start order: among stacks whose depends-on are satisfied, pick highest
# priority next (then name). Prints names one per line.
order_up() {
  remaining="$1"
  started=""

  n=0
  for _ in $remaining; do n=$((n + 1)); done
  n=$((n + 2))

  while [ -n "$(echo "$remaining" | xargs)" ] && [ "$n" -gt 0 ]; do
    n=$((n - 1))
    best=""
    best_pri=-999999
    next_remaining=""

    for s in $remaining; do
      ready=1
      for dep in $(stack_deps "$s"); do
        if ! runs_is_true "$dep"; then
          log "ERROR: $s depends on $dep but $dep.runs is not true"
          return 1
        fi
        case " $started " in
          *" $dep "*) ;;
          *) ready=0; break ;;
        esac
      done

      if [ "$ready" -eq 0 ]; then
        next_remaining="$next_remaining $s"
        continue
      fi

      pri="$(stack_priority "$s")"
      if [ -z "$best" ]; then
        best="$s"
        best_pri="$pri"
      elif [ "$pri" -gt "$best_pri" ]; then
        best="$s"
        best_pri="$pri"
      elif [ "$pri" -eq "$best_pri" ] && [ "$s" \< "$best" ]; then
        best="$s"
      fi
      next_remaining="$next_remaining $s"
    done

    if [ -z "$best" ]; then
      log "ERROR: dependency cycle or unsatisfied depends-on among:$remaining"
      return 1
    fi

    echo "$best"
    started="$started $best"

    remaining=""
    for s in $next_remaining; do
      if [ "$s" != "$best" ]; then
        remaining="$remaining $s"
      fi
    done
    remaining="$(echo "$remaining" | xargs)"
  done
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

  # Fail closed: only stacks with runs == true are started; everything else stops.
  for name in $(disabled_stack_names); do
    dir="$(stack_dir "$name")"
    if compose_file "$dir" >/dev/null 2>&1; then
      to_stop="$to_stop $name"
    fi
  done

  for name in $(enabled_stack_names); do
    dir="$(stack_dir "$name")"
    if compose_file "$dir" >/dev/null 2>&1; then
      to_start="$to_start $name"
    else
      log "WARN: $name.runs is true but no compose file in $dir — skipping"
    fi
  done

  ordered=""
  if ! ordered="$(order_up "$to_start")"; then
    notify "Homelab deploy failed" "dependency ordering failed; see git-sync logs" high
    return 1
  fi

  log "plan stop:$(fmt_list "$to_stop")"
  log "order up:$(fmt_list "$ordered")"

  had_failure=0
  stopped=""
  started=""
  recreated=""

  # Phase 1: stop every runs:false stack before touching enabled ones.
  log "Phase 1: stopping disabled stacks"
  for name in $(order_down "$to_stop"); do
    dir="$(stack_dir "$name")"
    if stack_running "$dir" 2>/dev/null; then
      if compose_down "$dir"; then
        stopped="${stopped} ${name}"
      else
        notify_stack_failed "stop" "$name"
        had_failure=1
      fi
    else
      log "skip  $name (already stopped)"
    fi
  done

  # Phase 2: apply compose up -d for runs:true stacks in priority order.
  log "Phase 2: applying enabled stacks"
  for name in $ordered; do
    dir="$(stack_dir "$name")"
    result="$(compose_up "$dir")" || {
      notify_stack_failed "up" "$name"
      had_failure=1
      continue
    }
    case "$result" in
      started) started="${started} ${name}" ;;
      recreated) recreated="${recreated} ${name}" ;;
      unchanged) log "skip  $name (unchanged)" ;;
    esac
  done

  log "applied stop:$(fmt_list "$stopped") start:$(fmt_list "$started") recreated:$(fmt_list "$recreated")"

  notify_msg=""
  if [ -n "$(echo "$stopped" | xargs)" ]; then
    notify_msg="${notify_msg}stopped: $(fmt_list "$stopped")
"
  fi
  if [ -n "$(echo "$started" | xargs)" ]; then
    notify_msg="${notify_msg}started: $(fmt_list "$started")
"
  fi
  if [ -n "$(echo "$recreated" | xargs)" ]; then
    notify_msg="${notify_msg}recreated: $(fmt_list "$recreated")
"
  fi
  if [ -n "$notify_msg" ]; then
    notify "Homelab update applied" "$notify_msg" default whale
  else
    log "No stack changes applied"
  fi

  if [ "$had_failure" -ne 0 ]; then
    log "Sync finished with failures"
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
      if [ -f "${REPO_DIR}/src/watchtower/git-sync.sh" ]; then
        sync_from_config || log "WARN: sync_from_config returned non-zero"
      else
        log "ERROR: ${REPO_DIR}/src/watchtower/git-sync.sh missing after pull"
        notify "Homelab deploy failed" "git-sync.sh missing after pull" high
      fi
    else
      log "ERROR: fast-forward merge failed (local divergence?). Skipping sync."
      notify "Homelab git-sync failed" "fast-forward merge failed on ${BRANCH}; sync skipped" high
    fi
  else
    log "Up to date at ${LOCAL}"
  fi

  sleep "$INTERVAL"
done
