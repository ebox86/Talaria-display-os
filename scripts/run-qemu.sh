#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${1:-${OUTPUT_DIR:-$repo_root/output}/images/disk.img}"
memory="${QEMU_MEMORY:-1024}"

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "qemu-system-x86_64 is required." >&2
  exit 1
fi

if [[ ! -f "$image" ]]; then
  echo "Image not found: $image" >&2
  echo "Run ./scripts/build.sh first or pass an explicit disk image path." >&2
  exit 1
fi

echo "Booting $image"
echo "QEMU uses IDE + e1000 to stay close to old workstation hardware."

exec qemu-system-x86_64 \
  -M pc \
  -m "$memory" \
  -drive "file=$image,format=raw,if=ide" \
  -nic user,model=e1000 \
  -vga std \
  -boot c
