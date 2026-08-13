#!/usr/bin/env bash
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This CI dependency installer currently supports apt-based Linux runners." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  bc \
  build-essential \
  bzip2 \
  ca-certificates \
  cpio \
  file \
  git \
  gzip \
  libelf-dev \
  libncurses-dev \
  patch \
  perl \
  python3 \
  rsync \
  tar \
  unzip \
  wget \
  xz-utils
