#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${OUTPUT_DIR:-$repo_root/output}"
images_dir="$output_dir/images"
artifact_root="${ARTIFACT_ROOT:-$repo_root/artifacts}"
bundle_dir="$artifact_root/talaria-display-os"
version="$(tr -d '[:space:]' < "$repo_root/buildroot-version.txt")"
git_sha="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo local)"
image_name="talaria-display-os-$version-$git_sha.img"
archive_name="talaria-display-os-$version-$git_sha.tar.gz"

write_sha256() {
  local file="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file"
  else
    shasum -a 256 "$file"
  fi
}

required_files=(
  "$images_dir/disk.img"
  "$images_dir/talaria-display-os-manifest.txt"
  "$images_dir/SHA256SUMS"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Expected build artifact missing: $file" >&2
    exit 1
  fi
done

rm -rf "$bundle_dir"
mkdir -p "$bundle_dir"

cp "$images_dir/disk.img" "$bundle_dir/$image_name"
cp "$images_dir/talaria-display-os-manifest.txt" "$bundle_dir/"
cp "$images_dir/SHA256SUMS" "$bundle_dir/"
cp "$repo_root/README.md" "$bundle_dir/"
cp "$repo_root/docs/build-and-boot.md" "$bundle_dir/"
cp "$repo_root/docs/first-boot-test.md" "$bundle_dir/"
cp "$repo_root/docs/hardware-inventory.md" "$bundle_dir/"

(
  cd "$bundle_dir"
  write_sha256 "$image_name" > "$image_name.sha256"
)

tar -C "$artifact_root" -czf "$artifact_root/$archive_name" talaria-display-os

echo "Packaged image bundle: $artifact_root/$archive_name"
