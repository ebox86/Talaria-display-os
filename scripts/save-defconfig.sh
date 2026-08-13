#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$repo_root/buildroot-version.txt")"
buildroot_dir="${BUILDROOT_DIR:-$repo_root/.build/buildroot-$version}"
output_dir="${OUTPUT_DIR:-$repo_root/output}"
dl_dir="${BR2_DL_DIR:-$repo_root/dl}"
defconfig="${DEFCONFIG:-talaria_display_x86_64_defconfig}"
defconfig_path="$repo_root/external/configs/$defconfig"

if [[ ! -d "$buildroot_dir" ]]; then
  echo "Buildroot was not found at $buildroot_dir" >&2
  echo "Run ./scripts/bootstrap-buildroot.sh or set BUILDROOT_DIR." >&2
  exit 1
fi

if [[ ! -f "$defconfig_path" ]]; then
  echo "Defconfig was not found at $defconfig_path" >&2
  exit 1
fi

mkdir -p "$output_dir" "$dl_dir"
export BR2_DL_DIR="$dl_dir"

echo "Loading $defconfig"
make -C "$buildroot_dir" O="$output_dir" BR2_EXTERNAL="$repo_root/external" "$defconfig"

echo "Saving minimal defconfig to $defconfig_path"
make -C "$buildroot_dir" O="$output_dir" BR2_EXTERNAL="$repo_root/external" BR2_DEFCONFIG="$defconfig_path" savedefconfig

echo "Defconfig saved: $defconfig_path"
