#!/usr/bin/env bash
# Exercise S80talaria-browser's init-level process cleanup without
# requiring the real WPE/Cog/Cage binaries.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init_script="$repo_root/external/board/talaria/display-x86_64/rootfs_overlay/etc/init.d/S80talaria-browser"
work_dir="$(mktemp -d)"

pass_count=0
fail_count=0

cleanup() {
  if [[ -f "$work_dir/supervisor.pid" ]]; then
    kill "$(cat "$work_dir/supervisor.pid")" 2>/dev/null || true
  fi
  if [[ -f "$work_dir/browser.process.pid" ]]; then
    kill "$(cat "$work_dir/browser.process.pid")" 2>/dev/null || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

cat > "$work_dir/fake-supervisor" <<'EOF'
#!/bin/sh
echo "$$" >> "$FAKE_SUPERVISOR_LOG"
mkdir -p "$TALARIA_BROWSER_RUN_DIR/browser-supervise.lock"
echo "$$" > "$TALARIA_BROWSER_RUN_DIR/browser-supervise.lock/pid"
trap 'exit 0' INT TERM
while true; do sleep 100; done
EOF
chmod +x "$work_dir/fake-supervisor"

cat > "$work_dir/fake-browser" <<'EOF'
#!/bin/sh
echo "$$" > "$FAKE_BROWSER_PIDFILE"
sleep 100 &
sleep_pid=$!
trap 'kill "$sleep_pid" 2>/dev/null; exit 0' INT TERM
wait "$sleep_pid"
EOF
chmod +x "$work_dir/fake-browser"

cat > "$work_dir/pidof" <<'EOF'
#!/bin/sh
if [ "$1" = "fake-browser" ] && [ -f "$FAKE_BROWSER_PIDFILE" ]; then
  pid="$(cat "$FAKE_BROWSER_PIDFILE" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "$pid"
  fi
fi
EOF
chmod +x "$work_dir/pidof"

run_init() {
  PATH="$work_dir:$PATH" \
  TALARIA_BROWSER_SUPERVISOR_CMD="$work_dir/fake-supervisor" \
  TALARIA_BROWSER_SUPERVISOR_PIDFILE="$work_dir/supervisor.pid" \
  TALARIA_BROWSER_PIDFILE="$work_dir/browser.pid" \
  TALARIA_BROWSER_RUN_DIR="$work_dir/run" \
  TALARIA_BROWSER_CMD="$work_dir/fake-browser" \
  FAKE_SUPERVISOR_LOG="$work_dir/supervisor.log" \
  FAKE_BROWSER_PIDFILE="$work_dir/browser.process.pid" \
    sh "$init_script" "$1"
}

wait_for_file() {
  local file="$1" timeout="${2:-10}" waited=0
  while [[ "$waited" -lt "$timeout" ]]; do
    [[ -s "$file" ]] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

check() {
  local name="$1" ok="$2"
  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $name"
    echo "--- supervisor log ---"
    cat "$work_dir/supervisor.log" 2>/dev/null || echo "(empty)"
    fail_count=$((fail_count + 1))
  fi
}

mkdir -p "$work_dir/run"
: > "$work_dir/supervisor.log"

ok=1
run_init start
wait_for_file "$work_dir/supervisor.pid" || ok=0
run_init start
sleep 1
supervisor_count="$(wc -l < "$work_dir/supervisor.log" | tr -d '[:space:]')"
[[ "$supervisor_count" -eq 1 ]] || ok=0
check "start is idempotent while supervisor pidfile is live" "$ok"

ok=1
rm -f "$work_dir/supervisor.pid"
run_init start
sleep 1
supervisor_count="$(wc -l < "$work_dir/supervisor.log" | tr -d '[:space:]')"
[[ "$supervisor_count" -eq 1 ]] || ok=0
[[ -s "$work_dir/supervisor.pid" ]] || ok=0
check "start adopts an active supervisor lock instead of duplicating" "$ok"

ok=1
FAKE_BROWSER_PIDFILE="$work_dir/browser.process.pid" "$work_dir/fake-browser" &
browser_pid=$!
wait_for_file "$work_dir/browser.process.pid" || ok=0
echo "$browser_pid" > "$work_dir/browser.pid"
run_init stop
wait "$browser_pid" 2>/dev/null || true
kill -0 "$browser_pid" 2>/dev/null && ok=0
[[ ! -e "$work_dir/run/browser-supervise.lock" ]] || ok=0
check "stop removes orphaned browser process and stale lock" "$ok"

echo
echo "$pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
