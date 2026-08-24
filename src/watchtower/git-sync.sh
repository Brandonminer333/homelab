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
# Host path for docker compose (daemon labels use host paths, not /homelab).
HOST_REPO_DIR="${HOST_REPO_DIR:-$REPO_DIR}"
BRANCH="${GIT_BRANCH:-main}"
INTERVAL="${POLL_INTERVAL:-300}"
# Desired stack state is always the public YAML in-repo (not .env).
CONFIG_FILE="${REPO_DIR}/src/watchtower/config.yml"
STATUS_FILE="${REPO_DIR}/.git-sync-status"
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

compose_file_rel() {
  dir="$1"
  if [ -f "${REPO_DIR}/${dir}/docker-compose.yml" ]; then
    echo "docker-compose.yml"
    return 0
  fi
  if [ -f "${REPO_DIR}/${dir}/compose.yml" ]; then
    echo "compose.yml"
    return 0
  fi
  return 1
}

compose_file() {
  dir="$1"
  rel="$(compose_file_rel "$dir")" || return 1
  echo "${REPO_DIR}/${dir}/${rel}"
}

compose_project_dir() {
  echo "${HOST_REPO_DIR}/$1"
}

# -f must use REPO_DIR (readable in-container); --project-directory uses HOST_REPO_DIR
# so compose matches containers labeled with the host clone path.
compose_invoke() {
  dir="$1"
  shift
  local_file="$(compose_file "$dir")" || return 1
  docker compose -f "$local_file" --project-directory "$(compose_project_dir "$dir")" "$@"
}

# True if any container in the compose project is running.
stack_running() {
  dir="$1"
  compose_file_rel "$dir" >/dev/null || return 1

  ids="$(compose_invoke "$dir" ps -q --status running 2>/dev/null || true)"
  if [ -n "$ids" ]; then
    return 0
  fi

  project="$(basename "$dir")"
  ids="$(docker ps -q \
    --filter "label=com.docker.compose.project=${project}" \
    --filter "status=running" 2>/dev/null || true)"
  if [ -n "$ids" ]; then
    return 0
  fi

  local_file="$(compose_file "$dir")"
  for cname in $(yq -r '.services[].container_name // empty' "$local_file" 2>/dev/null); do
    if [ -n "$cname" ] && docker inspect -f '{{.State.Running}}' "$cname" 2>/dev/null | grep -qx true; then
      return 0
    fi
  done
  return 1
}

compose_down() {
  dir="$1"
  compose_file_rel "$dir" >/dev/null || {
    log "WARN: no compose file in $dir"
    return 1
  }
  log "down  $dir"
  compose_invoke "$dir" down
}

# Sorted container IDs for a stack (one line, space-separated).
stack_container_ids() {
  dir="$1"
  compose_invoke "$dir" ps -q 2>/dev/null | sort | tr '\n' ' '
}

# Apply compose up -d. On success prints one of: started, recreated, unchanged.
compose_up() {
  dir="$1"
  compose_file_rel "$dir" >/dev/null || {
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
  if ! compose_invoke "$dir" up -d 1>&2; then
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

# All runs:true stacks including watchtower (for plan display only).
all_enabled_stack_names() {
  yq -r '
    .containers
    | to_entries[]
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

read_status_field() {
  field="$1"
  if [ -f "$STATUS_FILE" ]; then
    grep "^${field}=" "$STATUS_FILE" 2>/dev/null | cut -d= -f2- || true
  fi
}

# Usage: write_status STATE PHASE CURRENT UP_ORDER UP_INDEX UP_TOTAL
write_status() {
  state="$1"
  phase="$2"
  current="$3"
  up_order="$4"
  up_index="$5"
  up_total="$6"
  {
    echo "state=${state}"
    echo "phase=${phase}"
    echo "current=${current}"
    echo "up_order=${up_order}"
    echo "up_index=${up_index}"
    echo "up_total=${up_total}"
    echo "updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$STATUS_FILE"
}

# Sets DEPLOY_TO_STOP, DEPLOY_TO_START, DEPLOY_ORDERED_UP (space-separated).
build_deploy_plan() {
  DEPLOY_TO_STOP=""
  DEPLOY_TO_START=""
  DEPLOY_ORDERED_UP=""

  for name in $(disabled_stack_names); do
    dir="$(stack_dir "$name")"
    if compose_file "$dir" >/dev/null 2>&1; then
      DEPLOY_TO_STOP="$DEPLOY_TO_STOP $name"
    fi
  done
  DEPLOY_TO_STOP="$(echo "$DEPLOY_TO_STOP" | xargs)"

  for name in $(enabled_stack_names); do
    dir="$(stack_dir "$name")"
    if compose_file "$dir" >/dev/null 2>&1; then
      DEPLOY_TO_START="$DEPLOY_TO_START $name"
    else
      log "WARN: $name.runs is true but no compose file in $dir — skipping"
    fi
  done
  DEPLOY_TO_START="$(echo "$DEPLOY_TO_START" | xargs)"

  if ! DEPLOY_ORDERED_UP="$(order_up "$DEPLOY_TO_START")"; then
    return 1
  fi
  DEPLOY_ORDERED_UP="$(echo "$DEPLOY_ORDERED_UP" | xargs)"
  return 0
}

# Full up order including watchtower (plan/status display only).
build_plan_display() {
  if ! build_deploy_plan; then
    return 1
  fi
  PLAN_TO_STOP="$DEPLOY_TO_STOP"
  to_start_all=""
  for name in $(all_enabled_stack_names); do
    dir="$(stack_dir "$name")"
    if compose_file "$dir" >/dev/null 2>&1; then
      to_start_all="$to_start_all $name"
    fi
  done
  to_start_all="$(echo "$to_start_all" | xargs)"
  if ! PLAN_ORDERED_UP="$(order_up "$to_start_all")"; then
    return 1
  fi
  PLAN_ORDERED_UP="$(echo "$PLAN_ORDERED_UP" | xargs)"
  return 0
}

stack_run_label() {
  name="$1"
  dir="$(stack_dir "$name")"
  if stack_running "$dir" 2>/dev/null; then
    echo running
  else
    echo stopped
  fi
}

print_up_order_progress() {
  order="$1"
  current="$2"
  seen_current=0
  for name in $order; do
    if [ "$seen_current" -eq 0 ] && [ "$name" = "$current" ]; then
      printf '  [current]  %s\n' "$name"
      seen_current=1
    elif [ "$seen_current" -eq 1 ]; then
      printf '  [pending]  %s\n' "$name"
    else
      printf '  [done]     %s\n' "$name"
    fi
  done
}

ensure_config_ready() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config not found at $CONFIG_FILE" >&2
    return 1
  fi
  if ! command -v yq >/dev/null 2>&1; then
    echo "ERROR: yq is required to parse $CONFIG_FILE" >&2
    return 1
  fi
  return 0
}

cmd_plan() {
  ensure_config_ready || return 1
  if ! build_plan_display; then
    echo "ERROR: dependency ordering failed" >&2
    return 1
  fi

  stop_count=0
  for _ in $PLAN_TO_STOP; do stop_count=$((stop_count + 1)); done
  up_count=0
  for _ in $PLAN_ORDERED_UP; do up_count=$((up_count + 1)); done

  echo "Phase 1 stop order (${stop_count} stacks):"
  if [ "$stop_count" -eq 0 ]; then
    echo "  (none)"
  else
    for name in $(order_down "$PLAN_TO_STOP"); do
      label="$(stack_run_label "$name")"
      printf '  [%s]  %s\n' "$label" "$name"
    done
  fi

  echo ""
  echo "Phase 2 up order (${up_count} stacks):"
  if [ "$up_count" -eq 0 ]; then
    echo "  (none)"
  else
    for name in $PLAN_ORDERED_UP; do
      label="$(stack_run_label "$name")"
      if [ "$name" = "watchtower" ]; then
        printf '  [%s]  %s (self-managed)\n' "$label" "$name"
      else
        printf '  [%s]  %s\n' "$label" "$name"
      fi
    done
  fi
}

cmd_status() {
  ensure_config_ready || return 1

  state="$(read_status_field state)"
  phase="$(read_status_field phase)"
  current="$(read_status_field current)"
  up_order="$(read_status_field up_order)"
  up_index="$(read_status_field up_index)"
  up_total="$(read_status_field up_total)"
  updated_at="$(read_status_field updated_at)"

  if [ "$state" = "syncing" ]; then
    if [ "$phase" = "up" ]; then
      echo "syncing — phase 2: up (${up_index}/${up_total})"
    else
      echo "syncing — phase 1: stop"
    fi
    echo "current: ${current:-unknown}"
    echo ""
    if [ "$phase" = "up" ] && [ -n "$up_order" ]; then
      print_up_order_progress "$up_order" "$current"
    fi
    return 0
  fi

  if [ "$phase" = "done" ] && [ -n "$updated_at" ]; then
    echo "idle (last sync finished ${updated_at})"
  elif [ "$phase" = "error" ] && [ -n "$updated_at" ]; then
    echo "idle (last sync failed ${updated_at})"
  else
    echo "idle"
  fi
  echo ""
  cmd_plan
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

  if ! build_deploy_plan; then
    write_status idle error "" "" 0 0
    notify "Homelab deploy failed" "dependency ordering failed; see git-sync logs" high
    return 1
  fi

  to_stop="$DEPLOY_TO_STOP"
  ordered="$DEPLOY_ORDERED_UP"

  up_total=0
  for _ in $ordered; do up_total=$((up_total + 1)); done

  log "plan stop:$(fmt_list "$to_stop")"
  log "order up:$(fmt_list "$ordered")"

  write_status syncing stop "" "$ordered" 0 "$up_total"

  had_failure=0
  stopped=""
  started=""
  recreated=""
  last_current=""

  # Phase 1: stop every runs:false stack before touching enabled ones.
  log "Phase 1: stopping disabled stacks"
  for name in $(order_down "$to_stop"); do
    last_current="$name"
    write_status syncing stop "$name" "$ordered" 0 "$up_total"
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
  up_index=0
  for name in $ordered; do
    up_index=$((up_index + 1))
    last_current="$name"
    write_status syncing up "$name" "$ordered" "$up_index" "$up_total"
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
    write_status idle error "$last_current" "$ordered" "$up_index" "$up_total"
    log "Sync finished with failures"
    return 1
  fi

  write_status idle done "" "$ordered" "$up_total" "$up_total"
  log "Sync finished"
}

cd "$REPO_DIR"

case "${1:-}" in
  plan)
    cmd_plan
    exit $?
    ;;
  status)
    cmd_status
    exit $?
    ;;
esac

# Bind-mounted repos often fail ownership checks when the container runs as root.
git config --global --add safe.directory "$REPO_DIR"

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
