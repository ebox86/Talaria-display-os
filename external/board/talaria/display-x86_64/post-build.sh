#!/usr/bin/env bash
set -euo pipefail

target_dir="$1"
board_dir="$(cd "$(dirname "$0")" && pwd)"

copy_grub_boot_img() {
  local inferred_build_dir last_candidate
  local -a candidates=()

  if [[ -z "${BINARIES_DIR:-}" ]]; then
    echo "BINARIES_DIR is not set; cannot stage GRUB boot.img for genimage." >&2
    return 1
  fi

  if [[ -f "$target_dir/lib/grub/i386-pc/boot.img" ]]; then
    candidates+=("$target_dir/lib/grub/i386-pc/boot.img")
  fi

  if [[ -n "${BUILD_DIR:-}" && -d "$BUILD_DIR" ]]; then
    while IFS= read -r candidate; do
      candidates+=("$candidate")
    done < <(find "$BUILD_DIR" -path '*/build-i386-pc/grub-core/boot.img' -type f 2>/dev/null | sort)
  fi

  inferred_build_dir="$(cd "$target_dir/.." && pwd)/build"
  if [[ -d "$inferred_build_dir" && "$inferred_build_dir" != "${BUILD_DIR:-}" ]]; then
    while IFS= read -r candidate; do
      candidates+=("$candidate")
    done < <(find "$inferred_build_dir" -path '*/build-i386-pc/grub-core/boot.img' -type f 2>/dev/null | sort)
  fi

  if (( ${#candidates[@]} == 0 )); then
    echo "Could not find GRUB i386-pc boot.img. genimage requires $BINARIES_DIR/boot.img." >&2
    return 1
  fi

  last_candidate="${candidates[$(( ${#candidates[@]} - 1 ))]}"
  cp -f "$last_candidate" "$BINARIES_DIR/boot.img"
  echo "Staged GRUB BIOS boot sector -> $BINARIES_DIR/boot.img"
}

mkdir -p "$target_dir/data/talaria"
mkdir -p "$target_dir/boot/grub"
mkdir -p "$target_dir/usr/share/talaria"
cp -f "$board_dir/grub-bios.cfg" "$target_dir/boot/grub/grub.cfg"
cp -f "$board_dir/assets/talaria-splash.png" "$target_dir/usr/share/talaria/talaria-splash.png"

find "$target_dir/etc/init.d" -maxdepth 1 -type f -name 'S*talaria-*' -exec chmod 0755 {} +
find "$target_dir/usr/bin" -maxdepth 1 -type f -name 'talaria-*' -exec chmod 0755 {} +

copy_grub_boot_img

echo "Talaria Display OS rootfs prepared at $target_dir"
