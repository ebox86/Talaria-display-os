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
  BR2_PACKAGE_MESA3D_OPENGL_ES
  BR2_PACKAGE_MESA3D_GBM
  BR2_PACKAGE_MESA3D_GALLIUM_DRIVER_SOFTPIPE
  # These two are what wpewebkit's Config.in actually `depends on` -
  # checking them directly, not just the Mesa options that are supposed
  # to provide them, is what would have caught the MESA3D_OPENGL_ES2-
  # doesn't-exist bug (iteration 1) instead of it silently cascading
  # into wpewebkit/cog failing for a reason one step removed from the
  # actual defconfig typo.
  BR2_PACKAGE_HAS_LIBEGL
  BR2_PACKAGE_HAS_LIBGLES
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

# General safety net beyond the specific symbols above: Buildroot marks
# ANY deprecated/renamed option with `select BR2_LEGACY` when it's set
# (e.g. MESA3D_GALLIUM_DRIVER_SWRAST -> _SOFTPIPE, found this way in
# iteration 2). A legacy option can still resolve to 'y' and pass every
# check above while silently hard-stopping the next real Buildroot
# invocation (`Makefile.legacy: You have legacy configuration`), so
# check for BR2_LEGACY itself rather than only the specific renames
# already known about.
if grep -qx 'BR2_LEGACY=y' "$config_file"; then
  echo "$config_file sets a deprecated/renamed Buildroot option (BR2_LEGACY=y)." >&2
  echo "This resolves fine but hard-stops the next real build step. Find which" >&2
  echo "option in external/configs/talaria_display_x86_64_defconfig it is by" >&2
  echo "cross-referencing against Buildroot's own Config.in.legacy, e.g.:" >&2
  echo "  grep -oE '^BR2_[A-Z0-9_]+' external/configs/talaria_display_x86_64_defconfig |" >&2
  echo "    xargs -I{} grep -l '^config {}\$' \$BUILDROOT_DIR/Config.in.legacy" >&2
  exit 1
fi

# Cog's Wayland platform (COG_PLATFORM_FDO) defaults to 'y' in Cog's own
# Config.in and was never meant to be built here - only --platform=drm is
# ever launched at runtime (see talaria-browser-supervise) - but it pulls
# in cairo, which nothing else in this defconfig provides, so it fails
# ~3+ hours in, after WPEWebKit itself has already built from source
# (iteration 4). Check for it explicitly so a future re-enable (e.g. an
# unrelated defconfig edit that resets it to its Kconfig default) fails
# in seconds instead of silently reintroducing that multi-hour loss.
if grep -qx 'BR2_PACKAGE_COG_PLATFORM_FDO=y' "$config_file"; then
  echo "$config_file has BR2_PACKAGE_COG_PLATFORM_FDO=y." >&2
  echo "This platform is unused at runtime (only --platform=drm is ever launched)" >&2
  echo "and fails on a missing cairo dependency after WPEWebKit has already built" >&2
  echo "from source (~3+ hours). Set '# BR2_PACKAGE_COG_PLATFORM_FDO is not set' in" >&2
  echo "external/configs/talaria_display_x86_64_defconfig instead." >&2
  exit 1
fi

echo "Browser-stack packages resolved correctly in $config_file, no legacy options set."
