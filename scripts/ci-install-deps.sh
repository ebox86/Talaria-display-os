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
  curl \
  diffutils \
  file \
  findutils \
  gawk \
  git \
  gzip \
  libelf-dev \
  libncurses-dev \
  make \
  patch \
  perl \
  python3 \
  qemu-system-x86 \
  rsync \
  sed \
  tar \
  unzip \
  wget \
  xz-utils \
  autoconf \
  automake \
  bison \
  cmake \
  flex \
  gperf \
  libtool \
  ninja-build \
  pkg-config \
  ruby \
  texinfo

# Buildroot builds most of its own host tool dependencies from source
# (host-cmake, host-ninja, etc.), so the extras above are a best-effort
# list for whatever the WPEWebKit/Cog/Mesa host build additionally
# expects to already be on PATH. Not verified against an actual build;
# if a build fails on a missing host tool, add it here.
