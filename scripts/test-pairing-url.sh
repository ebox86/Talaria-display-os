#!/usr/bin/env bash
# Exercise the local pairing page generator without Cog/WPE.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pairing_url="$repo_root/external/board/talaria/display-x86_64/rootfs_overlay/usr/bin/talaria-pairing-url"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

pass_count=0
fail_count=0

check() {
  local name="$1" ok="$2"
  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: $name"
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $name"
    fail_count=$((fail_count + 1))
  fi
}

screen_source_dir="$repo_root/external/board/talaria/display-x86_64/rootfs_overlay/usr/share/talaria/screens"

url="$(
  TALARIA_DEVICE_ID=display-01 \
  TALARIA_PAIRING_CODE=A7K4-92B1 \
  TALARIA_SERVER_BASE_URL=http://talaria.local:17444 \
  TALARIA_PAIRING_SCREEN_SOURCE_DIR="$screen_source_dir" \
  TALARIA_PAIRING_SCREEN_DIR="$work_dir/screens" \
  TALARIA_ASSIGNMENT_FETCH_STATUS=disabled \
  TALARIA_ASSIGNMENT_SOURCE=local \
  TALARIA_ASSIGNMENT_REFRESH_SECONDS=15 \
    "$pairing_url"
)"

ok=1
[[ "$url" == file://"$work_dir"/screens/pairing.html* ]] || ok=0
[[ -f "$work_dir/screens/pairing.html" ]] || ok=0
[[ -f "$work_dir/screens/pairing.json" ]] || ok=0
grep -q '"code": "A7K4-92B1"' "$work_dir/screens/pairing.json" || ok=0
grep -q '"deviceId": "display-01"' "$work_dir/screens/pairing.json" || ok=0
grep -q '"server": "http://talaria.local:17444"' "$work_dir/screens/pairing.json" || ok=0
grep -q 'code=A7K4-92B1' <<<"$url" || ok=0
grep -q 'deviceId=display-01' <<<"$url" || ok=0
grep -q 'http-equiv="refresh"' "$work_dir/screens/pairing.html" && ok=0
check "stages handoff pairing page with dynamic fields" "$ok"

ok=1
grep -q '"qrScheme": "talaria://display/pair"' "$work_dir/screens/pairing.json" || ok=0
grep -q '"deviceToken": ""' "$work_dir/screens/pairing.json" || ok=0
grep -q '"nonce": "' "$work_dir/screens/pairing.json" || ok=0
check "keeps QR payload short-lived and credential-free" "$ok"

blocked_code_path="$work_dir/pairing-code-dir"
mkdir -p "$blocked_code_path"
url_one="$(
  TALARIA_DEVICE_ID=display-01 \
  TALARIA_PAIRING_CODE_FILE="$blocked_code_path" \
  TALARIA_PAIRING_SCREEN_SOURCE_DIR="$screen_source_dir" \
  TALARIA_PAIRING_SCREEN_DIR="$work_dir/blocked-screens" \
    "$pairing_url"
)"
url_two="$(
  TALARIA_DEVICE_ID=display-01 \
  TALARIA_PAIRING_CODE_FILE="$blocked_code_path" \
  TALARIA_PAIRING_SCREEN_SOURCE_DIR="$screen_source_dir" \
  TALARIA_PAIRING_SCREEN_DIR="$work_dir/blocked-screens" \
    "$pairing_url"
)"
ok=1
[[ "$url_one" == "$url_two" ]] || ok=0
check "keeps pairing URL stable when code cannot be persisted" "$ok"

echo
echo "$pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
