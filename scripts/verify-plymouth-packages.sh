#!/usr/bin/env bash
# Fail fast if the local Plymouth package or its runtime dependencies do not
# resolve in Buildroot's generated .config.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${OUTPUT_DIR:-$repo_root/output}"
config_file="$output_dir/.config"

if [[ ! -f "$config_file" ]]; then
  echo "No resolved Buildroot config at $config_file." >&2
  echo "Run 'make <defconfig>' first (scripts/build.sh does this before the full build)." >&2
  exit 1
fi

required_symbols=(
  BR2_PACKAGE_PLYMOUTH
  BR2_PACKAGE_HAS_UDEV
  BR2_PACKAGE_FREETYPE
  BR2_PACKAGE_LIBDRM
  BR2_PACKAGE_LIBEVDEV
  BR2_PACKAGE_LIBPNG
  BR2_PACKAGE_LIBXKBCOMMON
  BR2_PACKAGE_XKEYBOARD_CONFIG
)

missing=()
for symbol in "${required_symbols[@]}"; do
  grep -qx "${symbol}=y" "$config_file" || missing+=("$symbol")
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "The following Plymouth packages did not resolve to 'y' in $config_file:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

if grep -qx 'BR2_LEGACY=y' "$config_file"; then
  echo "$config_file sets a deprecated/renamed Buildroot option (BR2_LEGACY=y)." >&2
  exit 1
fi

echo "Plymouth packages resolved correctly in $config_file, no legacy options set."
