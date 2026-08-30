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

decode_data_url() {
  local url="$1"
  printf '%s' "${url#data:text/html;base64,}" | base64 -d
}

url="$(
  TALARIA_DEVICE_ID=display-01 \
  TALARIA_PAIRING_CODE=A7K4-92B1 \
  TALARIA_SERVER_BASE_URL=http://talaria.local:17444 \
  TALARIA_ASSIGNMENT_FETCH_STATUS=disabled \
  TALARIA_ASSIGNMENT_REFRESH_SECONDS=15 \
    "$pairing_url"
)"

html="$(decode_data_url "$url")"
ok=1
[[ "$url" == data:text/html\;base64,* ]] || ok=0
grep -q 'A7K4-92B1' <<<"$html" || ok=0
grep -q 'display-01' <<<"$html" || ok=0
grep -q 'Ready to pair' <<<"$html" || ok=0
grep -q 'Assignment Poll' <<<"$html" || ok=0
grep -q 'http-equiv="refresh"' <<<"$html" && ok=0
check "renders pairing page without browser-side refresh" "$ok"

blocked_code_path="$work_dir/pairing-code-dir"
mkdir -p "$blocked_code_path"
url_one="$(
  TALARIA_DEVICE_ID=display-01 \
  TALARIA_PAIRING_CODE_FILE="$blocked_code_path" \
    "$pairing_url"
)"
url_two="$(
  TALARIA_DEVICE_ID=display-01 \
  TALARIA_PAIRING_CODE_FILE="$blocked_code_path" \
    "$pairing_url"
)"
ok=1
[[ "$url_one" == "$url_two" ]] || ok=0
check "keeps pairing URL stable when code cannot be persisted" "$ok"

echo
echo "$pass_count passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]
