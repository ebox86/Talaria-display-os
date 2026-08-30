#!/usr/bin/env bash
# Verify browser runtime files in the final target rootfs after Buildroot
# finishes. Kconfig symbol checks catch misspelled options early; this catches
# packages that resolved and built but did not leave the runtime files Cog/WPE
# need on the image.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${OUTPUT_DIR:-$repo_root/output}"
target_dir="${TARGET_DIR:-$output_dir/target}"

if [[ ! -d "$target_dir" ]]; then
  echo "No Buildroot target rootfs at $target_dir." >&2
  echo "Run the full image build first (scripts/build.sh does this)." >&2
  exit 1
fi

missing=()

[[ -x "$target_dir/usr/bin/cage" ]] || missing+=("/usr/bin/cage")
[[ -x "$target_dir/usr/bin/cog" ]] || missing+=("/usr/bin/cog")

if ! find "$target_dir/usr/lib" -type f -name 'libcogplatform-wl.so*' -print -quit 2>/dev/null | grep -q .; then
  missing+=("/usr/lib/.../libcogplatform-wl.so")
fi

if ! find "$target_dir/usr/lib" -type f -name 'libcogplatform-drm.so*' -print -quit 2>/dev/null | grep -q .; then
  missing+=("/usr/lib/.../libcogplatform-drm.so")
fi

if ! find "$target_dir/usr/lib" -type f -name 'libWPEBackend-fdo-1.0.so*' -print -quit 2>/dev/null | grep -q .; then
  missing+=("/usr/lib/libWPEBackend-fdo-1.0.so")
fi

if [[ ! -e "$target_dir/usr/lib/libWPEBackend-default.so" ]]; then
  missing+=("/usr/lib/libWPEBackend-default.so")
fi

if ((${#missing[@]} > 0)); then
  echo "The final target rootfs is missing browser runtime files:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo >&2
  echo "The image may boot, but Cage/Cog/WPE will not render a browser." >&2
  exit 1
fi

echo "Browser runtime files are present in $target_dir."
