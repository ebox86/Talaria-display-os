#!/usr/bin/env bash
# Fail fast if the broad-video-coverage kernel config fragment
# (board/talaria/display-x86_64/linux-video.fragment) didn't actually
# land in the generated kernel .config. Same reasoning as
# verify-browser-packages.sh: a wrong/renamed Kconfig symbol is
# silently dropped rather than erroring, so without this check a bad
# symbol here would only surface as "no display on some hardware" after
# the fact. scripts/build.sh runs this automatically, after
# `make linux-configure` and before the full build.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${OUTPUT_DIR:-$repo_root/output}"

config_file="$(find "$output_dir/build" -maxdepth 2 -iname '.config' -ipath '*linux*' 2>/dev/null | head -n1)"

if [[ -z "$config_file" ]]; then
  echo "Could not find a generated Linux kernel .config under $output_dir/build." >&2
  echo "Run 'make linux-configure' first (scripts/build.sh does this automatically" >&2
  echo "when the defconfig references a kernel config fragment)." >&2
  exit 1
fi

required_symbols=(
  CONFIG_DRM
  CONFIG_DRM_FBDEV_EMULATION
  CONFIG_DRM_SIMPLEDRM
  CONFIG_DRM_QXL
  CONFIG_DRM_VIRTIO_GPU
  CONFIG_DRM_VMWGFX
  CONFIG_FB_VESA
  CONFIG_INPUT_EVDEV
  CONFIG_AGP
  CONFIG_AGP_INTEL
  CONFIG_VIRTIO_PCI
  CONFIG_VIRTIO_INPUT
)

missing=()
for symbol in "${required_symbols[@]}"; do
  grep -qx "${symbol}=y" "$config_file" || missing+=("$symbol")
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "The following video-fragment symbols did not resolve to 'y' in $config_file:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo >&2
  echo "This usually means a Kconfig symbol name in" >&2
  echo "board/talaria/display-x86_64/linux-video.fragment is wrong, doesn't apply to" >&2
  echo "kernel 6.12, or lost a dependency. Check with:" >&2
  echo "  make -C \$BUILDROOT_DIR O=$output_dir linux-menuconfig" >&2
  exit 1
fi

echo "Video-fragment kernel config resolved correctly in $config_file."
