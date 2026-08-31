#!/usr/bin/env bash
# Verify Plymouth and Talaria theme files in the final target rootfs.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${OUTPUT_DIR:-$repo_root/output}"
target_dir="${TARGET_DIR:-$output_dir/target}"
theme_dir="$target_dir/usr/share/plymouth/themes/talaria"

if [[ ! -d "$target_dir" ]]; then
  echo "No Buildroot target rootfs at $target_dir." >&2
  echo "Run the full image build first (scripts/build.sh does this)." >&2
  exit 1
fi

missing=()

[[ -x "$target_dir/usr/bin/plymouth" ]] || missing+=("/usr/bin/plymouth")
[[ -x "$target_dir/usr/sbin/plymouthd" ]] || missing+=("/usr/sbin/plymouthd")
[[ -x "$target_dir/etc/init.d/S05plymouth" ]] || missing+=("/etc/init.d/S05plymouth")
[[ -f "$target_dir/etc/plymouth/plymouthd.conf" ]] || missing+=("/etc/plymouth/plymouthd.conf")
[[ -f "$theme_dir/talaria.plymouth" ]] || missing+=("/usr/share/plymouth/themes/talaria/talaria.plymouth")
[[ -f "$theme_dir/talaria.script" ]] || missing+=("/usr/share/plymouth/themes/talaria/talaria.script")
[[ -f "$theme_dir/assets/wordmark.png" ]] || missing+=("/usr/share/plymouth/themes/talaria/assets/wordmark.png")
[[ -f "$target_dir/usr/share/talaria/screens/pairing.html" ]] || missing+=("/usr/share/talaria/screens/pairing.html")

if ((${#missing[@]} > 0)); then
  echo "The final target rootfs is missing Plymouth/theme runtime files:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

echo "Plymouth runtime files are present in $target_dir."
