#!/usr/bin/env bash
# Exercise usr/bin/talaria-resolve-mode's validation/fallback logic
# directly on the build host, without a Buildroot image or QEMU. This
# only checks the shell logic itself; it does not validate init
# sequencing, chmod bits, or actual boot behavior — see
# scripts/qemu-smoke-test.sh for that.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$repo_root/external/board/talaria/display-x86_64/rootfs_overlay/usr/bin/talaria-resolve-mode"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

pass_count=0
fail_count=0

# run_case NAME ETC_CONTENT DATA_CONTENT PING_CMD EXPECT_MODE EXPECT_FALLBACK(yes/no)
run_case() {
  local name="$1" etc_content="$2" data_content="$3" ping_cmd="$4" expect_mode="$5" expect_fallback="$6"
  local etc_conf="$work_dir/$name.etc.conf"
  local data_conf="$work_dir/$name.data.conf"
  local state_log="$work_dir/$name.log"

  if [[ -n "$etc_content" ]]; then
    printf '%s\n' "$etc_content" > "$etc_conf"
  else
    etc_conf="$work_dir/$name.etc.missing"
  fi

  if [[ -n "$data_content" ]]; then
    printf '%s\n' "$data_content" > "$data_conf"
  else
    data_conf="$work_dir/$name.data.missing"
  fi

  TALARIA_ETC_CONF="$etc_conf" \
  TALARIA_DATA_CONF="$data_conf" \
  TALARIA_STATE_LOG="$state_log" \
  TALARIA_PING_CMD="$ping_cmd" \
    sh "$resolver" >/dev/null 2>&1 || true

  local ok=1
  if ! grep -q "effective_mode: $expect_mode" "$state_log" 2>/dev/null; then
    ok=0
  fi
  if [[ "$expect_fallback" == "yes" ]] && ! grep -q '^fallback_reason:' "$state_log" 2>/dev/null; then
    ok=0
  fi
  if [[ "$expect_fallback" == "no" ]] && grep -q '^fallback_reason:' "$state_log" 2>/dev/null; then
    ok=0
  fi

  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $name"
    echo "--- $state_log ---"
    cat "$state_log" 2>/dev/null || echo "(no state log written)"
    fail_count=$((fail_count + 1))
  fi
}

run_case "valid-dashboard-reachable" \
  "" \
  "TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=http://talaria.local:5173/dashboard/
TALARIA_SERVER_HOST=talaria.local" \
  "true" \
  "dashboard" "no"

run_case "valid-signage-reachable" \
  "" \
  "TALARIA_DISPLAY_MODE=signage
TALARIA_DISPLAY_URL=http://talaria.local:5173/signage/
TALARIA_SERVER_HOST=talaria.local" \
  "true" \
  "signage" "no"

run_case "explicit-diagnostics-no-url-needed" \
  "" \
  "TALARIA_DISPLAY_MODE=diagnostics" \
  "false" \
  "diagnostics" "no"

run_case "invalid-mode-value" \
  "" \
  "TALARIA_DISPLAY_MODE=bogus" \
  "true" \
  "diagnostics" "yes"

run_case "missing-url" \
  "" \
  "TALARIA_DISPLAY_MODE=dashboard" \
  "true" \
  "diagnostics" "yes"

run_case "malformed-url" \
  "" \
  "TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=talaria.local/dashboard" \
  "true" \
  "diagnostics" "yes"

run_case "unreachable-server" \
  "" \
  "TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=http://talaria.local:5173/dashboard/
TALARIA_SERVER_HOST=talaria.local" \
  "false" \
  "diagnostics" "yes"

run_case "no-config-at-all-still-resolves" \
  "" \
  "" \
  "true" \
  "diagnostics" "yes"

run_case "data-override-wins-over-etc" \
  "TALARIA_DISPLAY_MODE=diagnostics" \
  "TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=http://talaria.local:5173/dashboard/
TALARIA_SERVER_HOST=talaria.local" \
  "true" \
  "dashboard" "no"

echo
echo "$pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
