#!/usr/bin/env bash
set -euo pipefail

target_dir="$1"
board_dir="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$target_dir/data/talaria"
mkdir -p "$target_dir/boot/grub"
cp -f "$board_dir/grub-bios.cfg" "$target_dir/boot/grub/grub.cfg"

find "$target_dir/etc/init.d" -maxdepth 1 -type f -name 'S*talaria-*' -exec chmod 0755 {} +
if [[ -f "$target_dir/usr/bin/talaria-splash" ]]; then
  chmod 0755 "$target_dir/usr/bin/talaria-splash"
fi

if [[ -n "${HOST_DIR:-}" && -f "$HOST_DIR/lib/grub/i386-pc/boot.img" && -n "${BINARIES_DIR:-}" ]]; then
  cp -f "$HOST_DIR/lib/grub/i386-pc/boot.img" "$BINARIES_DIR"
fi

echo "Talaria Dashboard OS rootfs prepared at $target_dir"
