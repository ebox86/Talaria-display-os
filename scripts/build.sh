#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$repo_root/buildroot-version.txt")"
buildroot_dir="${BUILDROOT_DIR:-$repo_root/.build/buildroot-$version}"
output_dir="${OUTPUT_DIR:-$repo_root/output}"
dl_dir="${BR2_DL_DIR:-$repo_root/dl}"
defconfig="${DEFCONFIG:-talaria_display_x86_64_defconfig}"

repair_grub2_image_cache() {
  local config_file="$output_dir/.config"
  local -a image_stamps=()

  [[ -f "$config_file" ]] || return 0
  grep -qx 'BR2_TARGET_GRUB2_I386_PC=y' "$config_file" || return 0
  [[ ! -f "$output_dir/images/grub.img" ]] || return 0

  # CI restores output/build but not output/images. If a previous cache
  # contains grub2's image-install stamp, Buildroot can believe grub.img
  # already exists even though genimage will later fail looking for it.
  # Remove only that stamp so the normal grub2 install-images step
  # recreates output/images/grub.img during the full build.
  shopt -s nullglob
  image_stamps=("$output_dir"/build/grub2-*/.stamp_images_installed)
  shopt -u nullglob

  if ((${#image_stamps[@]} > 0)); then
    rm -f "${image_stamps[@]}"
    echo "Invalidated cached GRUB2 image-install stamp; output/images/grub.img will be regenerated."
  fi
}

repair_browser_runtime_cache() {
  local config_file="$output_dir/.config"
  local target_dir="$output_dir/target"
  local -a stamps=()

  [[ -f "$config_file" ]] || return 0

  if grep -qx 'BR2_PACKAGE_COG_PLATFORM_FDO=y' "$config_file" \
    && [[ -d "$output_dir/build" ]] \
    && [[ ! -e "$target_dir/usr/lib/cog/modules/libcogplatform-wl.so" ]] \
    && ! find "$target_dir/usr/lib" -type f -name 'libcogplatform-wl.so*' -print -quit 2>/dev/null | grep -q .; then
    shopt -s nullglob
    stamps=("$output_dir"/build/cog-*/.stamp_configured "$output_dir"/build/cog-*/.stamp_built "$output_dir"/build/cog-*/.stamp_target_installed "$output_dir"/build/cog-*/.stamp_staging_installed)
    shopt -u nullglob
    if ((${#stamps[@]} > 0)); then
      rm -f "${stamps[@]}"
      echo "Invalidated cached Cog build/install stamps; Wayland platform module will be regenerated."
    fi
  fi

  if grep -qx 'BR2_PACKAGE_WPEBACKEND_FDO=y' "$config_file" \
    && [[ -d "$output_dir/build" ]] \
    && [[ ! -e "$target_dir/usr/lib/libWPEBackend-fdo-1.0.so" ]] \
    && ! find "$target_dir/usr/lib" -type f -name 'libWPEBackend-fdo-1.0.so*' -print -quit 2>/dev/null | grep -q .; then
    shopt -s nullglob
    stamps=("$output_dir"/build/wpebackend-fdo-*/.stamp_configured "$output_dir"/build/wpebackend-fdo-*/.stamp_built "$output_dir"/build/wpebackend-fdo-*/.stamp_target_installed "$output_dir"/build/wpebackend-fdo-*/.stamp_staging_installed)
    shopt -u nullglob
    if ((${#stamps[@]} > 0)); then
      rm -f "${stamps[@]}"
      echo "Invalidated cached wpebackend-fdo build/install stamps; WPE backend library will be regenerated."
    fi
  fi
}

if [[ ! -d "$buildroot_dir" ]]; then
  echo "Buildroot was not found at $buildroot_dir" >&2
  echo "Run ./scripts/bootstrap-buildroot.sh or set BUILDROOT_DIR." >&2
  exit 1
fi

mkdir -p "$output_dir" "$dl_dir"
export BR2_DL_DIR="$dl_dir"

echo "Configuring $defconfig"
make -C "$buildroot_dir" O="$output_dir" BR2_EXTERNAL="$repo_root/external" "$defconfig"

# The browser-stack Kconfig symbols are best-effort (see the comment
# block in the defconfig); catch a misspelled/renamed one in seconds,
# before the multi-hour build below, rather than after.
if grep -q '^BR2_PACKAGE_WPEWEBKIT=y' "$repo_root/external/configs/$defconfig" 2>/dev/null; then
  "$repo_root/scripts/verify-browser-packages.sh"
fi

if grep -q '^BR2_PACKAGE_PLYMOUTH=y' "$repo_root/external/configs/$defconfig" 2>/dev/null; then
  "$repo_root/scripts/verify-plymouth-packages.sh"
fi

# Same reasoning, one layer down: the video-coverage kernel config
# fragment's symbols are also best-effort. `linux-configure` runs just
# the kernel package's own configure step (source fetch + Kconfig
# merge), which is minutes, not the multi-hour full build.
if grep -q '^BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES=' "$repo_root/external/configs/$defconfig" 2>/dev/null; then
  echo "Configuring Linux kernel (verifying video fragment)"
  make -C "$buildroot_dir" O="$output_dir" BR2_EXTERNAL="$repo_root/external" linux-configure
  "$repo_root/scripts/verify-kernel-video-config.sh"
fi

repair_grub2_image_cache
repair_browser_runtime_cache

echo "Building Talaria Display OS"
make -C "$buildroot_dir" O="$output_dir"

if grep -q '^BR2_PACKAGE_WPEWEBKIT=y' "$repo_root/external/configs/$defconfig" 2>/dev/null; then
  "$repo_root/scripts/verify-browser-runtime-files.sh"
fi

if grep -q '^BR2_PACKAGE_PLYMOUTH=y' "$repo_root/external/configs/$defconfig" 2>/dev/null; then
  "$repo_root/scripts/verify-plymouth-runtime-files.sh"
fi

echo "Build complete. Images are under: $output_dir/images"
