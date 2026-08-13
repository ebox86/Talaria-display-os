#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$repo_root/buildroot-version.txt")"
build_dir="${BUILD_DIR:-$repo_root/.build}"
archive="$build_dir/buildroot-$version.tar.xz"
source_dir="$build_dir/buildroot-$version"
url="https://buildroot.org/downloads/buildroot-$version.tar.xz"

mkdir -p "$build_dir"

if [[ -d "$source_dir" ]]; then
  echo "Buildroot already present: $source_dir"
  exit 0
fi

if [[ ! -f "$archive" ]]; then
  echo "Downloading $url"
  if command -v curl >/dev/null 2>&1; then
    curl -L "$url" -o "$archive"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$archive" "$url"
  else
    echo "curl or wget is required to download Buildroot." >&2
    exit 1
  fi
fi

echo "Extracting $archive"
tar -C "$build_dir" -xf "$archive"
echo "Buildroot ready: $source_dir"
