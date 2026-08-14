#!/usr/bin/env bash
# Exercise usr/bin/talaria-browser-supervise's launch/restart/stop logic
# against a fake "browser" binary, without WPE/Cog or a Buildroot image.
# This only checks the supervision loop itself; the real cog/WPE
# invocation still needs a Linux Buildroot build + hardware or QEMU to
# validate — see scripts/qemu-smoke-test.sh and docs/display-runtime-design.md.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
supervisor="$repo_root/external/board/talaria/display-x86_64/rootfs_overlay/usr/bin/talaria-browser-supervise"
work_dir="$(mktemp -d)"

pass_count=0
fail_count=0
supervise_pid=""

cleanup() {
  if [[ -n "$supervise_pid" ]]; then
    kill "$supervise_pid" 2>/dev/null || true
  fi
  pkill -f "$work_dir/fake-browser" 2>/dev/null || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

cat > "$work_dir/fake-browser" <<'EOF'
#!/bin/sh
# Records its own invocation, then either exits immediately (to
# simulate a crash) or sleeps as a stand-in for a running browser.
echo "$(date) args: $*" >> "$FAKE_BROWSER_LOG"
if [ "${FAKE_BROWSER_CRASH:-0}" = "1" ]; then
  exit 0
fi
sleep 100
EOF
chmod +x "$work_dir/fake-browser"

write_state() {
  local mode="$1" url="$2"
  {
    echo "EFFECTIVE_MODE=$mode"
    echo "DISPLAY_URL=$url"
    echo "FALLBACK_REASON="
  } > "$work_dir/mode-state.conf"
}

wait_for() {
  local file="$1" pattern="$2" timeout="${3:-10}" waited=0
  while [[ "$waited" -lt "$timeout" ]]; do
    grep -q "$pattern" "$file" 2>/dev/null && return 0
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
    echo "--- console log ---"
    cat "$work_dir/console.log" 2>/dev/null || echo "(empty)"
    fail_count=$((fail_count + 1))
  fi
}

start_supervisor() {
  : > "$work_dir/console.log"
  : > "$work_dir/fake-browser.log"
  rm -rf "$work_dir/run"
  mkdir -p "$work_dir/run"
  TALARIA_MODE_STATE="$work_dir/mode-state.conf" \
  TALARIA_BROWSER_CMD="$work_dir/fake-browser" \
  TALARIA_BROWSER_POLL_INTERVAL=1 \
  TALARIA_BROWSER_RUN_DIR="$work_dir/run" \
  TALARIA_CONSOLE_DEVICE="$work_dir/console.log" \
  FAKE_BROWSER_LOG="$work_dir/fake-browser.log" \
  FAKE_BROWSER_CRASH="${1:-0}" \
    sh "$supervisor" &
  supervise_pid=$!
}

stop_supervisor() {
  kill "$supervise_pid" 2>/dev/null || true
  wait "$supervise_pid" 2>/dev/null || true
  supervise_pid=""
  pkill -f "$work_dir/fake-browser" 2>/dev/null || true
}

# --- Scenario 1: launches on a valid dashboard state ---
write_state "dashboard" "http://talaria.local/dashboard/"
start_supervisor
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_LAUNCH url=http://talaria.local/dashboard/' || ok=0
grep -q 'args: --platform=drm http://talaria.local/dashboard/' "$work_dir/fake-browser.log" 2>/dev/null || ok=0
check "launches on valid dashboard state" "$ok"

# --- Scenario 2: falling back to diagnostics stops the browser ---
write_state "diagnostics" ""
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_STOPPED mode=diagnostics' || ok=0
sleep 1
pgrep -f "$work_dir/fake-browser" >/dev/null 2>&1 && ok=0
check "stops browser on fallback to diagnostics" "$ok"

# --- Scenario 3: switching URLs restarts the browser ---
write_state "dashboard" "http://talaria.local/dashboard-v2/"
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_LAUNCH url=http://talaria.local/dashboard-v2/' || ok=0
check "restarts browser when the target URL changes" "$ok"

stop_supervisor

# --- Scenario 4: crash is detected and the browser is relaunched ---
write_state "dashboard" "http://talaria.local/dashboard/"
start_supervisor 1
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_CRASHED' 10 || ok=0
launch_count="$(grep -c 'TALARIA_BROWSER_LAUNCH' "$work_dir/console.log" 2>/dev/null)"
launch_count="${launch_count:-0}"
[[ "$launch_count" -ge 2 ]] || ok=0
check "detects a crashed browser and relaunches it" "$ok"

stop_supervisor

echo
echo "$pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
