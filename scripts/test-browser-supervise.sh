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
  sleep "${FAKE_BROWSER_RUNTIME:-0}"
  exit 0
fi
sleep 100
EOF
chmod +x "$work_dir/fake-browser"

cat > "$work_dir/fake-cage" <<'EOF'
#!/bin/sh
echo "$(date) cage args: $*" >> "$FAKE_BROWSER_LOG"
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  mkdir -p "$XDG_RUNTIME_DIR"
  if [ -e "$XDG_RUNTIME_DIR/wayland-0.lock" ]; then
    echo "$(date) stale wayland lock was not cleaned" >> "$FAKE_BROWSER_LOG"
    exit 70
  fi
  : > "$XDG_RUNTIME_DIR/wayland-0.lock"
fi
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
  shift
done
[ "$#" -gt 0 ] && shift
exec "$@"
EOF
chmod +x "$work_dir/fake-cage"

write_state() {
  local mode="$1" url="$2"
  {
    printf 'EFFECTIVE_MODE="%s"\n' "$mode"
    printf 'DISPLAY_URL="%s"\n' "$url"
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
  # $1=crash-mode $2=backoff_base $3=backoff_max $4=browser_runtime
  # $5=stable_cycles $6=giveup_retry_delay.
  # Defaults keep backoff effectively out of the way
  # (1s, same as poll interval) for scenarios that aren't specifically
  # testing backoff timing.
  : > "$work_dir/console.log"
  : > "$work_dir/fake-browser.log"
  rm -rf "$work_dir/run"
  mkdir -p "$work_dir/run"
  TALARIA_MODE_STATE="$work_dir/mode-state.conf" \
  TALARIA_BROWSER_BACKEND=drm \
  TALARIA_BROWSER_CMD="$work_dir/fake-browser" \
  TALARIA_BROWSER_POLL_INTERVAL=1 \
  TALARIA_BROWSER_BACKOFF_BASE="${2:-1}" \
  TALARIA_BROWSER_BACKOFF_MAX="${3:-1}" \
  TALARIA_BROWSER_STABLE_CYCLES="${5:-12}" \
  TALARIA_BROWSER_GIVEUP_RETRY_DELAY="${6:-1}" \
  TALARIA_BROWSER_CLEANUP_DELAY=0 \
  TALARIA_BROWSER_LOG="$work_dir/browser.log" \
  TALARIA_BROWSER_RUN_DIR="$work_dir/run" \
  TALARIA_CONSOLE_DEVICE="$work_dir/console.log" \
  FAKE_BROWSER_LOG="$work_dir/fake-browser.log" \
  FAKE_BROWSER_CRASH="${1:-0}" \
  FAKE_BROWSER_RUNTIME="${4:-0}" \
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
wait_for "$work_dir/fake-browser.log" 'args: --platform=drm http://talaria.local/dashboard/' || ok=0
check "launches on valid dashboard state" "$ok"

# --- Scenario 1b: auto backend launches through Cage/Cog Wayland when available ---
stop_supervisor
write_state "dashboard" "http://talaria.local/dashboard/"
: > "$work_dir/console.log"
: > "$work_dir/fake-browser.log"
rm -rf "$work_dir/run"
mkdir -p "$work_dir/run"
TALARIA_MODE_STATE="$work_dir/mode-state.conf" \
TALARIA_BROWSER_CMD="$work_dir/fake-browser" \
TALARIA_CAGE_CMD="$work_dir/fake-cage" \
TALARIA_BROWSER_POLL_INTERVAL=1 \
TALARIA_BROWSER_CLEANUP_DELAY=0 \
TALARIA_BROWSER_LOG="$work_dir/browser.log" \
TALARIA_BROWSER_RUN_DIR="$work_dir/run" \
TALARIA_CONSOLE_DEVICE="$work_dir/console.log" \
FAKE_BROWSER_LOG="$work_dir/fake-browser.log" \
  sh "$supervisor" &
supervise_pid=$!
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_LAUNCH url=http://talaria.local/dashboard/' || ok=0
wait_for "$work_dir/fake-browser.log" 'cage args: -s --' || ok=0
wait_for "$work_dir/fake-browser.log" 'args: --platform=wl http://talaria.local/dashboard/' || ok=0
check "auto backend launches through Cage and Cog Wayland" "$ok"

# --- Scenario 1c: a duplicate supervisor exits instead of launching a
#     second DRM browser owner against the same display.
ok=1
TALARIA_MODE_STATE="$work_dir/mode-state.conf" \
TALARIA_BROWSER_CMD="$work_dir/fake-browser" \
TALARIA_CAGE_CMD="$work_dir/fake-cage" \
TALARIA_BROWSER_POLL_INTERVAL=1 \
TALARIA_BROWSER_CLEANUP_DELAY=0 \
TALARIA_BROWSER_LOG="$work_dir/browser.log" \
TALARIA_BROWSER_RUN_DIR="$work_dir/run" \
TALARIA_CONSOLE_DEVICE="$work_dir/console.log" \
FAKE_BROWSER_LOG="$work_dir/fake-browser.log" \
  sh "$supervisor" &
second_supervise_pid=$!
wait "$second_supervise_pid" 2>/dev/null || ok=0
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_SUPERVISOR_ALREADY_RUNNING' || ok=0
launch_count="$(grep -c 'TALARIA_BROWSER_LAUNCH' "$work_dir/console.log" 2>/dev/null)"
launch_count="${launch_count:-0}"
[[ "$launch_count" -eq 1 ]] || ok=0
check "prevents a duplicate supervisor from launching a second browser" "$ok"

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

# --- Scenario 3b: pairing mode launches the local pairing page ---
write_state "pairing" "file:///run/talaria/screens/pairing.html?code=A7K4-92B1"
start_supervisor
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_LAUNCH url=local-pairing' || ok=0
wait_for "$work_dir/fake-browser.log" 'args: --platform=drm file:///run/talaria/screens/pairing.html?code=A7K4-92B1' || ok=0
check "launches local pairing page in pairing mode" "$ok"

# --- Scenario 3c: a transient empty URL in a browser-capable mode does
#     not interrupt an already-rendering pairing page.
write_state "pairing" ""
sleep 2
ok=1
grep -q 'TALARIA_BROWSER_STOPPED mode=pairing' "$work_dir/console.log" 2>/dev/null && ok=0
launch_count="$(grep -c 'TALARIA_BROWSER_LAUNCH url=local-pairing' "$work_dir/console.log" 2>/dev/null)"
launch_count="${launch_count:-0}"
[[ "$launch_count" -eq 1 ]] || ok=0
check "keeps pairing browser alive during transient empty target" "$ok"

# --- Scenario 3d: a transient empty state file does not interrupt an
#     already-rendering browser; explicit diagnostics remains the stop signal.
: > "$work_dir/mode-state.conf"
sleep 2
ok=1
grep -q 'TALARIA_BROWSER_STOPPED mode=unknown' "$work_dir/console.log" 2>/dev/null && ok=0
launch_count="$(grep -c 'TALARIA_BROWSER_LAUNCH url=local-pairing' "$work_dir/console.log" 2>/dev/null)"
launch_count="${launch_count:-0}"
[[ "$launch_count" -eq 1 ]] || ok=0
check "keeps browser alive during transient empty state" "$ok"

stop_supervisor

wait_for_launch_count() {
  local file="$1" min_count="$2" timeout="${3:-10}" waited=0 count
  while [[ "$waited" -lt "$timeout" ]]; do
    count="$(grep -c 'TALARIA_BROWSER_LAUNCH' "$file" 2>/dev/null)"
    [[ "${count:-0}" -ge "$min_count" ]] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# --- Scenario 4: crash is detected and the browser is relaunched ---
write_state "dashboard" "http://talaria.local/dashboard/"
start_supervisor 1
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_CRASHED' 10 || ok=0
wait_for_launch_count "$work_dir/console.log" 2 10 || ok=0
check "detects a crashed browser and relaunches it" "$ok"

# --- Scenario 5: repeated crashes against the same target surface a
#     visible give-up signal, matching the default TALARIA_BROWSER_MAX_CRASHES=3.
#     Reuses the still-running crash-looping supervisor from scenario 4.
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_GIVING_UP target=http://talaria.local/dashboard/ attempts=3 retry_seconds=1' 15 || ok=0
giveup_count="$(grep -c 'TALARIA_BROWSER_GIVING_UP' "$work_dir/console.log" 2>/dev/null)"
giveup_count="${giveup_count:-0}"
[[ "$giveup_count" -eq 1 ]] || ok=0
check "surfaces a give-up signal after repeated crashes, only once" "$ok"

stop_supervisor

# --- Scenario 6: backoff actually delays the relaunch, not just gives
#     up eventually. poll_interval=1s, backoff_base=backoff_max=3s, so a
#     relaunch should not happen in the ~1s right after a crash but
#     should happen by ~3-4s after.
write_state "dashboard" "http://talaria.local/dashboard/"
start_supervisor 1 3 3
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_CRASHED' 10 || ok=0
launch_count_at_crash="$(grep -c 'TALARIA_BROWSER_LAUNCH' "$work_dir/console.log" 2>/dev/null)"
launch_count_at_crash="${launch_count_at_crash:-0}"
sleep 1
launch_count_mid_backoff="$(grep -c 'TALARIA_BROWSER_LAUNCH' "$work_dir/console.log" 2>/dev/null)"
launch_count_mid_backoff="${launch_count_mid_backoff:-0}"
[[ "$launch_count_mid_backoff" -eq "$launch_count_at_crash" ]] || ok=0
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_BACKOFF seconds=3 crash_count=1' 5 || ok=0
sleep 4
launch_count_after_backoff="$(grep -c 'TALARIA_BROWSER_LAUNCH' "$work_dir/console.log" 2>/dev/null)"
launch_count_after_backoff="${launch_count_after_backoff:-0}"
[[ "$launch_count_after_backoff" -gt "$launch_count_mid_backoff" ]] || ok=0
check "backoff delays the relaunch instead of retrying immediately" "$ok"

stop_supervisor

# --- Scenario 7: a browser can draw for a while and still be unhealthy.
#     It should not be counted as stable after only a few poll cycles; this
#     catches delayed DRM crashes like the UTM/Cog modeset crash observed
#     after NeverSSL rendered and redirected.
write_state "dashboard" "http://talaria.local/delayed-crash/"
start_supervisor 1 1 1 4 12
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_GIVING_UP target=http://talaria.local/delayed-crash/ attempts=3' 25 || ok=0
check "delayed crashes still reach the give-up signal" "$ok"

stop_supervisor

# --- Scenario 8: once a target is visibly marked unavailable, retry
#     much more slowly than the normal crash backoff.
write_state "dashboard" "http://talaria.local/giveup-delay/"
start_supervisor 1 1 1 0 12 5
ok=1
wait_for "$work_dir/console.log" 'TALARIA_BROWSER_GIVING_UP target=http://talaria.local/giveup-delay/ attempts=3 retry_seconds=5' 15 || ok=0
launch_count_at_giveup="$(grep -c 'TALARIA_BROWSER_LAUNCH' "$work_dir/console.log" 2>/dev/null)"
launch_count_at_giveup="${launch_count_at_giveup:-0}"
sleep 2
launch_count_mid_giveup_delay="$(grep -c 'TALARIA_BROWSER_LAUNCH' "$work_dir/console.log" 2>/dev/null)"
launch_count_mid_giveup_delay="${launch_count_mid_giveup_delay:-0}"
[[ "$launch_count_mid_giveup_delay" -eq "$launch_count_at_giveup" ]] || ok=0
sleep 5
launch_count_after_giveup_delay="$(grep -c 'TALARIA_BROWSER_LAUNCH' "$work_dir/console.log" 2>/dev/null)"
launch_count_after_giveup_delay="${launch_count_after_giveup_delay:-0}"
[[ "$launch_count_after_giveup_delay" -gt "$launch_count_mid_giveup_delay" ]] || ok=0
check "give-up state slows retries after repeated crashes" "$ok"

stop_supervisor

echo
echo "$pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
