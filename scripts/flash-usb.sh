#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: sudo $0 /dev/sdX path/to/image.img" >&2
  exit 1
fi

device="$1"
image="$2"

if [[ ! -b "$device" ]]; then
  echo "Device is not a block device: $device" >&2
  exit 1
fi

if [[ ! -f "$image" ]]; then
  echo "Image not found: $image" >&2
  exit 1
fi

case "$device" in
  /dev/sd*|/dev/nvme*|/dev/mmcblk*) ;;
  *)
    echo "Refusing unexpected device path: $device" >&2
    exit 1
    ;;
esac

echo "About to overwrite $device with $image"
echo "This destroys all data on $device."
printf 'Type YES to continue: '
read -r confirmation

if [[ "$confirmation" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

sync
dd if="$image" of="$device" bs=4M status=progress conv=fsync
sync
echo "Flash complete: $device"
