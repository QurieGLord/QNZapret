#!/usr/bin/env bash

set -eEuo pipefail

ACTION="${1:-status}"
RUNTIME_DIR="${2:-}"
SERVICE_UNIT_NAME="${3:-}"

if [[ -z "$RUNTIME_DIR" ]]; then
  echo "runtime directory is required" >&2
  exit 1
fi

BIN="$RUNTIME_DIR/bin/nfqws"
LISTS_DIR="$RUNTIME_DIR/lists"
PAYLOADS_DIR="$RUNTIME_DIR/payloads"
PROFILE_FILE="$RUNTIME_DIR/profiles/default.conf"
STATE_DIR="$RUNTIME_DIR/state"
LOG_DIR="$RUNTIME_DIR/logs"
PID_FILE="$STATE_DIR/nfqws.pid"
STATUS_FILE="$STATE_DIR/status.env"
RUNTIME_ENV="$STATE_DIR/runtime.env"
RULESET_FILE="$STATE_DIR/nzapret.nft"
HELPER_LOG="$LOG_DIR/service.log"
NFQWS_LOG="$LOG_DIR/nfqws.log"
TABLE_FAMILY="inet"
TABLE_NAME="nzapret_desktop"
MARK_MASK="0x40000000"
FORWARD_ENABLED="1"
NFQWS_DEBUG="${NFQWS_DEBUG:-1}"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-5}"
DAEMON_PID=""
DAEMON_ACTIVE="0"

mkdir -p "$LISTS_DIR" "$PAYLOADS_DIR" "$STATE_DIR" "$LOG_DIR" "$RUNTIME_DIR/profiles"

if [[ -f "$RUNTIME_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$RUNTIME_ENV"
fi

handle_unexpected_error() {
  local exit_code="$1"
  local command="$2"

  trap - ERR
  log_event ERROR "unexpected failure ($exit_code): $command"
  write_status 0 "" "Сбой helper-а: $command"
  echo "helper failure ($exit_code): $command" >&2
  exit "$exit_code"
}

trap 'handle_unexpected_error "$?" "$BASH_COMMAND"' ERR

log_event() {
  local event_type="$1"
  shift
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf '%s %-8s %s\n' "$timestamp" "$event_type" "$*" >> "$HELPER_LOG"
}

log_path_snapshot() {
  {
    printf '%s INFO     runtime snapshot\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    stat -c '  %A %a %U:%G %n' \
      "$RUNTIME_DIR" \
      "$BIN" \
      "$LISTS_DIR" \
      "$LISTS_DIR/list-general.txt" \
      "$LISTS_DIR/list-google.txt" \
      "$PAYLOADS_DIR" \
      "$PROFILE_FILE" 2>/dev/null || true
  } >> "$HELPER_LOG"
}

log_nfqws_tail() {
  {
    printf '%s INFO     nfqws log tail follows\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    tail -n 40 "$NFQWS_LOG" 2>/dev/null || true
  } >> "$HELPER_LOG"
}

log_process_status() {
  local pid="$1"

  {
    printf '%s INFO     process status pid=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid"
    grep -E '^(Name|Pid|PPid|Uid|Gid|Groups|CapInh|CapPrm|CapEff|CapBnd|CapAmb|NoNewPrivs|Seccomp|Seccomp_filters):' \
      "/proc/$pid/status" 2>/dev/null || true
  } >> "$HELPER_LOG"
}

build_nfqws_args() {
  NFQWS_ARGS=()
  if [[ "$NFQWS_DEBUG" == "1" ]]; then
    NFQWS_ARGS+=("--debug=1")
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ""|\#*|\;*)
        continue
        ;;
      *)
        NFQWS_ARGS+=("$line")
        ;;
    esac
  done < "$PROFILE_FILE"

  [[ "${#NFQWS_ARGS[@]}" -gt 0 ]] || fail "profile has no nfqws arguments"
}

wait_for_nfqws_startup() {
  local pid="$1"
  local second=1

  while [[ "$second" -le "$STARTUP_WAIT_SECONDS" ]]; do
    sleep 1
    if ! is_pid_running "$pid"; then
      rm -f "$PID_FILE"
      log_nfqws_tail
      fail "nfqws exited during startup, see $NFQWS_LOG"
    fi
    second=$((second + 1))
  done
}

write_status() {
  local running="$1"
  local pid="$2"
  local message="$3"
  local updated_at
  updated_at=$(date -Iseconds)
  cat > "$STATUS_FILE" <<EOF
running=$running
pid=$pid
message=$message
updated_at=$updated_at
table_family=$TABLE_FAMILY
table_name=$TABLE_NAME
EOF
}

fail() {
  local message="$1"
  log_event ERROR "$message"
  write_status 0 "" "$message"
  echo "$message" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

is_pid_running() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  [[ -d "/proc/$pid" ]]
}

cleanup_rules() {
  nft delete table "$TABLE_FAMILY" "$TABLE_NAME" >/dev/null 2>&1 || true
}

stop_existing_process() {
  local pid=""

  if [[ -f "$PID_FILE" ]]; then
    pid=$(tr -d '\r\n' < "$PID_FILE")
  fi

  if is_pid_running "$pid"; then
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
    if is_pid_running "$pid"; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  fi

  rm -f "$PID_FILE"
}

parse_profile() {
  QUEUE_NUM=""
  TCP_PORTS=""
  UDP_PORTS=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      --qnum=*)
        QUEUE_NUM="${line#--qnum=}"
        ;;
      --filter-tcp=*)
        if [[ -z "$TCP_PORTS" ]]; then
          TCP_PORTS="${line#--filter-tcp=}"
        else
          TCP_PORTS="$TCP_PORTS,${line#--filter-tcp=}"
        fi
        ;;
      --filter-udp=*)
        if [[ -z "$UDP_PORTS" ]]; then
          UDP_PORTS="${line#--filter-udp=}"
        else
          UDP_PORTS="$UDP_PORTS,${line#--filter-udp=}"
        fi
        ;;
    esac
  done < "$PROFILE_FILE"

  [[ -n "$QUEUE_NUM" ]] || fail "profile is missing --qnum"
  [[ -n "$TCP_PORTS" || -n "$UDP_PORTS" ]] || fail "profile has no tcp/udp filters"
}

append_queue_rule() {
  local proto="$1"
  local ports="$2"

  [[ -n "$ports" ]] || return 0
  ports=$(printf '%s' "$ports" | tr -d '[:space:]')
  printf '    %s dport { %s } queue num %s bypass\n' "$proto" "$ports" "$QUEUE_NUM" >> "$RULESET_FILE"
}

build_ruleset() {
  cat > "$RULESET_FILE" <<EOF
table $TABLE_FAMILY $TABLE_NAME {
  chain output {
    type filter hook output priority mangle; policy accept;
    meta mark & $MARK_MASK == $MARK_MASK return
    oifname "lo" return
    oifname "tun*" return
    oifname "tap*" return
    oifname "wg*" return
    oifname "tailscale*" return
    oifname "zt*" return
EOF

  append_queue_rule tcp "$TCP_PORTS"
  append_queue_rule udp "$UDP_PORTS"
  printf '  }\n' >> "$RULESET_FILE"

  if [[ "$FORWARD_ENABLED" == "1" ]]; then
    cat >> "$RULESET_FILE" <<EOF
  chain forward {
    type filter hook forward priority mangle; policy accept;
    meta mark & $MARK_MASK == $MARK_MASK return
    oifname "lo" return
    oifname "tun*" return
    oifname "tap*" return
    oifname "wg*" return
    oifname "tailscale*" return
    oifname "zt*" return
EOF
    append_queue_rule tcp "$TCP_PORTS"
    append_queue_rule udp "$UDP_PORTS"
    printf '  }\n' >> "$RULESET_FILE"
  fi

  printf '}\n' >> "$RULESET_FILE"
}

start_nfqws() {
  : > "$NFQWS_LOG"
  build_nfqws_args

  nohup "$BIN" "${NFQWS_ARGS[@]}" >> "$NFQWS_LOG" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  log_process_status "$pid"
  wait_for_nfqws_startup "$pid"

  log_event NFQWS "started pid=$pid"
  write_status 1 "$pid" "Сервис запущен."
  echo "Сервис запущен. PID $pid."
}

cleanup_daemon_runtime() {
  if [[ "$DAEMON_ACTIVE" != "1" ]]; then
    return
  fi

  DAEMON_ACTIVE="0"

  if is_pid_running "${DAEMON_PID:-}"; then
    trap - ERR
    kill "$DAEMON_PID" >/dev/null 2>&1 || true
    wait "$DAEMON_PID" >/dev/null 2>&1 || true
  fi

  rm -f "$PID_FILE"
  cleanup_rules
  log_event STOP "daemon stopped"
  write_status 0 "" "Сервис остановлен."
}

daemon_action() {
  require_cmd nft
  require_file "$BIN"
  require_file "$PROFILE_FILE"
  require_file "$LISTS_DIR/list-general.txt"
  require_file "$LISTS_DIR/list-google.txt"
  require_file "$PAYLOADS_DIR/quic_initial_www_google_com.bin"
  require_file "$PAYLOADS_DIR/tls_clienthello_www_google_com.bin"

  [[ -x "$BIN" ]] || fail "nfqws binary is not executable: $BIN"
  parse_profile
  stop_existing_process
  cleanup_rules
  build_ruleset
  log_path_snapshot
  nft -f "$RULESET_FILE" || fail "failed to apply nftables ruleset"
  log_event NFTABLES "rules applied queue=$QUEUE_NUM tcp=$TCP_PORTS udp=$UDP_PORTS"

  : > "$NFQWS_LOG"
  build_nfqws_args

  "$BIN" "${NFQWS_ARGS[@]}" >> "$NFQWS_LOG" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  log_process_status "$pid"
  wait_for_nfqws_startup "$pid"

  DAEMON_PID="$pid"
  DAEMON_ACTIVE="1"
  log_event NFQWS "daemon pid=$pid"
  write_status 1 "$pid" "nfqws started"

  trap 'cleanup_daemon_runtime' EXIT
  trap 'cleanup_daemon_runtime; exit 130' INT
  trap 'cleanup_daemon_runtime; exit 143' TERM

  local exit_code=0
  if wait "$pid"; then
    exit_code=0
  else
    exit_code=$?
  fi

  DAEMON_ACTIVE="0"
  DAEMON_PID=""
  rm -f "$PID_FILE"
  cleanup_rules

  if [[ "$exit_code" == "143" || "$exit_code" == "130" ]]; then
    log_event STOP "daemon stopped by signal code=$exit_code"
    write_status 0 "" "Сервис остановлен."
    trap - ERR
    return 0
  fi

  log_event NFQWS "daemon exited code=$exit_code"
  log_nfqws_tail
  write_status 0 "" "nfqws exited (code $exit_code)"
  trap - ERR
  return "$exit_code"
}

launch_service_action() {
  local unit="$SERVICE_UNIT_NAME"

  [[ -n "$unit" ]] || fail "systemd unit name is required"

  require_cmd systemctl
  require_cmd systemd-run

  write_status 0 "" "Запускаем сервис через systemd..."
  log_event SYSTEMD "launch unit=$unit"
  systemctl stop "$unit" >/dev/null 2>&1 || true
  systemd-run \
    --unit "$unit" \
    --collect \
    --property=Type=simple \
    --property=KillMode=control-group \
    --property=Restart=no \
    --property=NoNewPrivileges=no \
    --property=PrivateUsers=no \
    --quiet \
    "$0" daemon "$RUNTIME_DIR" >/dev/null || fail "failed to start transient systemd service"

  echo "Запрос на запуск через systemd отправлен."
}

start_action() {
  require_cmd nft
  require_file "$BIN"
  require_file "$PROFILE_FILE"
  require_file "$LISTS_DIR/list-general.txt"
  require_file "$LISTS_DIR/list-google.txt"
  require_file "$PAYLOADS_DIR/quic_initial_www_google_com.bin"
  require_file "$PAYLOADS_DIR/tls_clienthello_www_google_com.bin"

  [[ -x "$BIN" ]] || fail "nfqws binary is not executable: $BIN"
  parse_profile
  stop_existing_process
  cleanup_rules
  build_ruleset
  log_path_snapshot
  nft -f "$RULESET_FILE" || fail "failed to apply nftables ruleset"
  log_event NFTABLES "rules applied queue=$QUEUE_NUM tcp=$TCP_PORTS udp=$UDP_PORTS"
  start_nfqws
}

stop_action() {
  stop_existing_process
  cleanup_rules
  log_event STOP "service stopped"
  write_status 0 "" "Сервис остановлен."
  echo "Сервис остановлен."
}

status_action() {
  local pid=""
  local running=0

  if [[ -f "$PID_FILE" ]]; then
    pid=$(tr -d '\r\n' < "$PID_FILE")
  fi

  if is_pid_running "$pid"; then
    running=1
  else
    pid=""
  fi

  write_status "$running" "$pid" "Статус обновлён."
  printf 'running=%s pid=%s\n' "$running" "$pid"
}

case "$ACTION" in
  start)
    start_action
    ;;
  daemon)
    daemon_action
    ;;
  launch-service)
    launch_service_action
    ;;
  stop)
    stop_action
    ;;
  restart)
    stop_action
    start_action
    ;;
  status)
    status_action
    ;;
  *)
    fail "unsupported action: $ACTION"
    ;;
esac
