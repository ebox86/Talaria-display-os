#!/usr/bin/env bash
set -euo pipefail

# EFI counterpart to post-image.sh. The BIOS variant can use the plain
# support/scripts/genimage.sh wrapper because genimage-bios.cfg needs no
# runtime substitution. The EFI variant can't: genimage-efi.cfg's root
# partition UUID and grub-efi.cfg's root=PARTUUID= both need the actual
# generated filesystem UUID, which only exists after rootfs.ext2 is
# built. So this script invokes genimage directly itself, after doing
# that substitution - verified against Buildroot's own
# board/pc/post-image-efi.sh reference for this pinned version
# (2026.05.1), not guessed.
images_dir="${BINARIES_DIR:-}"
board_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$images_dir" ]]; then
  echo "BINARIES_DIR is not set; cannot build the EFI image." >&2
  exit 1
fi

uuid="$(dumpe2fs "$images_dir/rootfs.ext2" 2>/dev/null | sed -n 's/^Filesystem UUID: *\(.*\)/\1/p')"
if [[ -z "$uuid" ]]; then
  echo "Could not read a filesystem UUID from $images_dir/rootfs.ext2." >&2
  exit 1
fi

sed -i.bak "s/UUID_TMP/$uuid/g" "$images_dir/efi-part/EFI/BOOT/grub.cfg"
rm -f "$images_dir/efi-part/EFI/BOOT/grub.cfg.bak"
sed "s/UUID_TMP/$uuid/g" "$board_dir/genimage-efi.cfg" > "$images_dir/genimage-efi.cfg"

support/scripts/genimage.sh -c "$images_dir/genimage-efi.cfg"

git_commit="unknown"
if command -v git >/dev/null 2>&1; then
  git_commit="$(git -C "${BR2_EXTERNAL_TALARIA_DISPLAY_OS_PATH:-.}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

cat > "$images_dir/talaria-display-os-manifest.txt" <<EOF
Talaria Display OS EFI image artifacts
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Git commit: $git_commit
Boot mode: UEFI (GPT + ESP, grub-efi) - see docs/hardware-inventory.md
for BIOS-vs-UEFI target coverage.

Primary output:
- disk.img
- talaria-display-os-manifest.txt
- SHA256SUMS
EOF

(
  cd "$images_dir"
  if [[ -f disk.img ]]; then
    sha256sum disk.img > SHA256SUMS
  fi
)

echo "Wrote $images_dir/talaria-display-os-manifest.txt"
