#!/usr/bin/env bash
# Exercise usr/bin/talaria-resolve-mode's validation/fallback logic
# directly on the build host, without a Buildroot image or QEMU. This
# only checks the shell logic itself; it does not validate init
# sequencing, chmod bits, network reachability, or actual boot behavior — see
# scripts/qemu-smoke-test.sh for that.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$repo_root/external/board/talaria/display-x86_64/rootfs_overlay/usr/bin/talaria-resolve-mode"
pairing_url="$repo_root/external/board/talaria/display-x86_64/rootfs_overlay/usr/bin/talaria-pairing-url"
pairing_screen_source_dir="$repo_root/external/board/talaria/display-x86_64/rootfs_overlay/usr/share/talaria/screens"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

pass_count=0
fail_count=0

# run_case NAME ETC_CONTENT DATA_CONTENT UNUSED_REACHABILITY_CMD EXPECT_MODE EXPECT_FALLBACK(yes/no) [FETCH_CMD]
run_case() {
  local name="$1" etc_content="$2" data_content="$3" _unused_reachability_cmd="$4" expect_mode="$5" expect_fallback="$6"
  local fetch_cmd="${7:-}"
  local etc_conf="$work_dir/$name.etc.conf"
  local data_conf="$work_dir/$name.data.conf"
  local state_log="$work_dir/$name.log"
  local mode_state="$work_dir/$name.mode-state.conf"
  local resolver_status=0

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

  if [[ -n "$fetch_cmd" ]]; then
    TALARIA_ETC_CONF="$etc_conf" \
    TALARIA_DATA_CONF="$data_conf" \
    TALARIA_STATE_LOG="$state_log" \
    TALARIA_MODE_STATE="$mode_state" \
    TALARIA_PAIRING_URL_CMD="$pairing_url" \
    TALARIA_PAIRING_CODE_FILE="$work_dir/$name.pairing-code" \
    TALARIA_PAIRING_SCREEN_SOURCE_DIR="$pairing_screen_source_dir" \
    TALARIA_PAIRING_SCREEN_DIR="$work_dir/$name.screens" \
    TALARIA_FETCH_CMD="$fetch_cmd" \
      sh "$resolver" >/dev/null 2>&1 || resolver_status=$?
  else
    TALARIA_ETC_CONF="$etc_conf" \
    TALARIA_DATA_CONF="$data_conf" \
    TALARIA_STATE_LOG="$state_log" \
    TALARIA_MODE_STATE="$mode_state" \
    TALARIA_PAIRING_URL_CMD="$pairing_url" \
    TALARIA_PAIRING_CODE_FILE="$work_dir/$name.pairing-code" \
    TALARIA_PAIRING_SCREEN_SOURCE_DIR="$pairing_screen_source_dir" \
    TALARIA_PAIRING_SCREEN_DIR="$work_dir/$name.screens" \
      sh "$resolver" >/dev/null 2>&1 || resolver_status=$?
  fi

  local ok=1
  [[ "$resolver_status" -eq 0 ]] || ok=0
  if ! grep -q "effective_mode: $expect_mode" "$state_log" 2>/dev/null; then
    ok=0
  fi
  if [[ "$expect_fallback" == "yes" ]] && ! grep -q '^fallback_reason:' "$state_log" 2>/dev/null; then
    ok=0
  fi
  if [[ "$expect_fallback" == "no" ]] && grep -q '^fallback_reason:' "$state_log" 2>/dev/null; then
    ok=0
  fi

  # The browser supervisor's contract: DISPLAY_URL in mode-state.conf must
  # be empty whenever the effective mode is diagnostics or fallback fired,
  # and non-empty whenever it's a browser-capable mode.
  # shellcheck disable=SC1090
  . "$mode_state" 2>/dev/null || ok=0
  [[ "${EFFECTIVE_MODE:-}" == "$expect_mode" ]] || ok=0
  if [[ "$expect_mode" == "diagnostics" || "$expect_fallback" == "yes" ]]; then
    [[ -z "${DISPLAY_URL:-}" ]] || ok=0
  elif [[ "$expect_mode" == "pairing" ]]; then
    [[ "${DISPLAY_URL:-}" == file://"$work_dir"/"$name".screens/pairing.html* ]] || ok=0
  else
    [[ "${DISPLAY_URL:-}" == http* ]] || ok=0
  fi

  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $name"
    echo "--- $state_log ---"
    cat "$state_log" 2>/dev/null || echo "(no state log written)"
    echo "--- $mode_state ---"
    cat "$mode_state" 2>/dev/null || echo "(no mode-state file written)"
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

run_case "baked-default-pairing-no-url-needed" \
  "TALARIA_SERVER_HOST=talaria.local
TALARIA_DISPLAY_MODE=pairing
TALARIA_DISPLAY_URL=
TALARIA_DEVICE_ID=unconfigured" \
  "" \
  "false" \
  "pairing" "no"

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

run_case "server-host-ping-is-not-a-browser-gate" \
  "" \
  "TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=http://talaria.local:5173/dashboard/
TALARIA_SERVER_HOST=talaria.local" \
  "false" \
  "dashboard" "no"

run_case "no-config-at-all-still-resolves" \
  "" \
  "" \
  "true" \
  "diagnostics" "no"

run_case "data-override-wins-over-etc" \
  "TALARIA_DISPLAY_MODE=diagnostics" \
  "TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=http://talaria.local:5173/dashboard/
TALARIA_SERVER_HOST=talaria.local" \
  "true" \
  "dashboard" "no"

assignment_fetch="$work_dir/fetch-assignment"
cat > "$assignment_fetch" <<'EOF'
#!/bin/sh
printf '%s\n' \
  'TALARIA_DISPLAY_MODE="signage"' \
  'TALARIA_DISPLAY_URL="http://talaria.local:5173/dashboard/?mode=signage&deviceToken=1234"' \
  'TALARIA_SERVER_HOST="talaria.local"' \
  'TALARIA_ASSIGNMENT_REFRESH_SECONDS="30"'
EOF
chmod +x "$assignment_fetch"

run_case "server-assignment-overrides-local-config" \
  "" \
  "TALARIA_SERVER_BASE_URL=http://talaria.local:17444
TALARIA_DEVICE_ID=dev_test
TALARIA_DEVICE_TOKEN=1234
TALARIA_DISPLAY_MODE=diagnostics" \
  "true" \
  "signage" "no" \
  "$assignment_fetch"

assignment_fetch_pairing="$work_dir/fetch-assignment-pairing"
cat > "$assignment_fetch_pairing" <<'EOF'
#!/bin/sh
printf '%s\n' \
  'TALARIA_DISPLAY_MODE="pairing"' \
  'TALARIA_ASSIGNMENT_REFRESH_SECONDS="10"'
EOF
chmod +x "$assignment_fetch_pairing"

run_case "server-assignment-can-return-pairing" \
  "" \
  "TALARIA_SERVER_BASE_URL=http://talaria.local:17444
TALARIA_DEVICE_ID=dev_test
TALARIA_DEVICE_TOKEN=1234
TALARIA_DISPLAY_MODE=diagnostics" \
  "true" \
  "pairing" "no" \
  "$assignment_fetch_pairing"

stable_pairing_etc="$work_dir/stable-pairing.etc.conf"
stable_pairing_data="$work_dir/stable-pairing.data.conf"
stable_pairing_log="$work_dir/stable-pairing.log"
stable_pairing_state="$work_dir/stable-pairing.mode-state.conf"
printf '%s\n' \
  "TALARIA_DISPLAY_MODE=pairing" \
  "TALARIA_DEVICE_ID=display-01" \
  > "$stable_pairing_etc"
: > "$stable_pairing_data"
ok=1
TALARIA_ETC_CONF="$stable_pairing_etc" \
TALARIA_DATA_CONF="$stable_pairing_data" \
TALARIA_STATE_LOG="$stable_pairing_log" \
TALARIA_MODE_STATE="$stable_pairing_state" \
TALARIA_PAIRING_URL_CMD="$pairing_url" \
TALARIA_PAIRING_CODE_FILE="$work_dir/stable-pairing-code" \
TALARIA_PAIRING_SCREEN_SOURCE_DIR="$pairing_screen_source_dir" \
TALARIA_PAIRING_SCREEN_DIR="$work_dir/stable-pairing.screens" \
  sh "$resolver" >/dev/null 2>&1 || ok=0
# shellcheck disable=SC1090
. "$stable_pairing_state" 2>/dev/null || ok=0
first_pairing_url="${DISPLAY_URL:-}"
TALARIA_ETC_CONF="$stable_pairing_etc" \
TALARIA_DATA_CONF="$stable_pairing_data" \
TALARIA_STATE_LOG="$stable_pairing_log" \
TALARIA_MODE_STATE="$stable_pairing_state" \
TALARIA_PAIRING_URL_CMD="$pairing_url" \
TALARIA_PAIRING_CODE_FILE="$work_dir/stable-pairing-code" \
TALARIA_PAIRING_SCREEN_SOURCE_DIR="$pairing_screen_source_dir" \
TALARIA_PAIRING_SCREEN_DIR="$work_dir/stable-pairing.screens" \
  sh "$resolver" >/dev/null 2>&1 || ok=0
# shellcheck disable=SC1090
. "$stable_pairing_state" 2>/dev/null || ok=0
[[ "${DISPLAY_URL:-}" == "$first_pairing_url" ]] || ok=0
if compgen -G "$stable_pairing_state.*" >/dev/null; then
  ok=0
fi
if [[ "$ok" -eq 1 ]]; then
  echo "PASS: repeated pairing resolves keep browser URL stable"
  pass_count=$((pass_count + 1))
else
  echo "FAIL: repeated pairing resolves keep browser URL stable"
  echo "--- $stable_pairing_state ---"
  cat "$stable_pairing_state" 2>/dev/null || echo "(no mode-state file written)"
  fail_count=$((fail_count + 1))
fi

unsafe_fetch_marker="$work_dir/unsafe-fetch-was-called"
unsafe_assignment_fetch="$work_dir/unsafe-fetch-assignment"
cat > "$unsafe_assignment_fetch" <<EOF
#!/bin/sh
touch "$unsafe_fetch_marker"
exit 1
EOF
chmod +x "$unsafe_assignment_fetch"

run_case "unsafe-device-token-skips-assignment-fetch" \
  "" \
  "TALARIA_SERVER_BASE_URL=http://talaria.local:17444
TALARIA_DEVICE_ID=dev_test
TALARIA_DEVICE_TOKEN='not url safe'
TALARIA_DISPLAY_MODE=diagnostics" \
  "true" \
  "diagnostics" "no" \
  "$unsafe_assignment_fetch"
if [[ -e "$unsafe_fetch_marker" ]]; then
  echo "FAIL: unsafe device token still called assignment fetch"
  fail_count=$((fail_count + 1))
else
  echo "PASS: unsafe device token skipped assignment fetch"
  pass_count=$((pass_count + 1))
fi

assignment_fetch_fails="$work_dir/fetch-assignment-fails"
cat > "$assignment_fetch_fails" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$assignment_fetch_fails"

run_case "failed-server-assignment-keeps-local-config" \
  "" \
  "TALARIA_ASSIGNMENT_URL=http://talaria.local:17444/api/workflow/display/assignment.env
TALARIA_DEVICE_ID=dev_test
TALARIA_DEVICE_TOKEN=1234
TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=http://talaria.local:5173/dashboard/
TALARIA_SERVER_HOST=talaria.local" \
  "true" \
  "dashboard" "no" \
  "$assignment_fetch_fails"

shell_hazard_marker="$work_dir/shell-hazard-was-executed"
run_case "mode-state-quotes-shell-hazard-characters" \
  "" \
  "TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL='http://talaria.local:5173/dashboard/?q=\$(touch $shell_hazard_marker)&ok=1'
TALARIA_SERVER_HOST=talaria.local" \
  "true" \
  "dashboard" "no"
if [[ -e "$shell_hazard_marker" ]]; then
  echo "FAIL: mode-state executed command substitution while being sourced"
  fail_count=$((fail_count + 1))
else
  echo "PASS: mode-state did not execute command substitution while being sourced"
  pass_count=$((pass_count + 1))
fi

echo
echo "$pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
