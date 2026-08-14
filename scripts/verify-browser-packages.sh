#!/usr/bin/env bash
# Fail fast if the WPE/Cog browser-stack Kconfig symbols in
# external/configs/talaria_display_x86_64_defconfig didn't actually
# resolve to 'y' in the generated Buildroot .config. Run this right
# after `make <defconfig>` and before the full `make` build — a
# misspelled or renamed symbol is silently dropped by Buildroot's config
# system rather than erroring, so without this check a bad symbol name
# only shows up after a multi-hour WPEWebKit build produces the wrong
# image. scripts/build.sh runs this automatically.
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
  BR2_PACKAGE_LIBDRM
  BR2_PACKAGE_MESA3D
  BR2_PACKAGE_MESA3D_OPENGL_EGL
  BR2_PACKAGE_MESA3D_GBM
  BR2_PACKAGE_MESA3D_GALLIUM_DRIVER_SWRAST
  BR2_PACKAGE_WPEWEBKIT
  BR2_PACKAGE_COG
  BR2_PACKAGE_COG_PLATFORM_DRM
)

missing=()
for symbol in "${required_symbols[@]}"; do
  grep -qx "${symbol}=y" "$config_file" || missing+=("$symbol")
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "The following browser-stack packages did not resolve to 'y' in $config_file:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo >&2
  echo "This usually means a Kconfig symbol name in" >&2
  echo "external/configs/talaria_display_x86_64_defconfig is wrong, or the option moved" >&2
  echo "in this Buildroot version. Check with:" >&2
  echo "  make -C \$BUILDROOT_DIR O=$output_dir menuconfig" >&2
  exit 1
fi

echo "Browser-stack packages resolved correctly in $config_file."
