# Talaria Dashboard OS

USB-bootable Buildroot kiosk OS for Talaria dashboard displays.

This repo is the implementation workspace for the Talaria dashboard appliance proof of concept. It intentionally does not vendor Buildroot or commit generated images/toolchains. The repo owns the Buildroot external tree, Talaria-specific root filesystem overlay, build scripts, and hardware validation notes.

## Current Scope

Phase 1 is a text/network bring-up image:

```text
old PC boots USB/rootfs -> console splash -> BusyBox init -> wired DHCP -> logs config/network state
```

WPE WebKit/Cog is the intended kiosk browser stack, but browser work should start only after a minimal image boots and networks reliably on the oldest target PCs.

## Repo Layout

```text
buildroot-version.txt
scripts/
  build.sh
  bootstrap-buildroot.sh
  ci-install-deps.sh
  flash-usb.sh
  package-artifacts.sh
  run-qemu.sh
external/
  external.desc
  Config.in
  external.mk
  configs/
    talaria_dashboard_x86_64_defconfig
  board/
    talaria/
      dashboard-x86_64/
        genimage-bios.cfg
        grub-bios.cfg
        rootfs_overlay/
        post-build.sh
        post-image.sh
docs/
  build-and-boot.md
  first-boot-test.md
  hardware-inventory.md
```

## Prerequisites

Use a Linux build host or VM for actual Buildroot builds. macOS is fine for editing this repo, but Buildroot image generation and device flashing should happen on Linux.

Expected host tools:

- `bash`
- `make`
- `gcc`, `g++`
- `patch`
- `rsync`
- `file`
- `wget` or `curl`
- common archive tools such as `tar`, `xz`, `gzip`, `bzip2`

Buildroot will download source packages as needed. Keep the download cache outside git.

## Buildroot Version

The pinned Buildroot version is stored in:

```text
buildroot-version.txt
```

The initial pin is `2026.05.1`, the current stable bugfix release as of this bootstrap. If browser package compatibility becomes unstable, consider moving to the Buildroot LTS series after the first successful WPE/Cog build.

## Build

From the repo root:

```sh
./scripts/bootstrap-buildroot.sh
./scripts/build.sh
```

By default, scripts use:

```text
.build/buildroot-<version>/
output/
```

Override paths when needed:

```sh
BUILDROOT_DIR=/path/to/buildroot OUTPUT_DIR=/path/to/output ./scripts/build.sh
```

The expected Phase 1 disk image is:

```text
output/images/disk.img
```

Package the boot image, manifest, checksums, and test notes with:

```sh
./scripts/package-artifacts.sh
```

GitHub Actions also builds this image on pull requests and on pushes to `main`, then uploads the packaged artifact from the workflow run.

## QEMU

On a Linux host with QEMU installed:

```sh
./scripts/run-qemu.sh
```

The QEMU runner uses IDE storage and an e1000 NIC to stay closer to old workstation hardware than a virtio-only VM.

## Flashing

The initial scaffold does not assume a final USB image format yet. Once the first bootable image is emitted, use:

```sh
sudo ./scripts/flash-usb.sh /dev/sdX output/images/<image>.img
```

The flashing script is intentionally defensive and requires explicit confirmation.

## First Milestone

Success for the first real milestone:

```text
Old PC boots -> shows splash -> gets DHCP -> pings Talaria server -> writes /data/talaria/phase1.log
```

Do not start browser tuning until this is true on at least one old target workstation.

## Useful References

- Buildroot manual: https://buildroot.org/downloads/manual/manual.html
- Buildroot external trees: https://buildroot.org/downloads/manual/manual.html#outside-br-custom
- WPE WebKit: https://wpewebkit.org/
- BusyBox: https://busybox.net/about.html
