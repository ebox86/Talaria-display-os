# Talaria Display OS

USB-bootable Buildroot kiosk OS for Talaria-managed display endpoints.

This repo is the implementation workspace for Talaria display appliances: production dashboards, shop-floor status screens, and digital signage endpoints. It intentionally does not vendor Buildroot or commit generated images/toolchains. The repo owns the Buildroot external tree, Talaria-specific root filesystem overlay, build scripts, and hardware validation notes.

## Current Scope

Phase 1 is a display/network bring-up image:

```text
old PC boots USB/rootfs -> framebuffer PNG splash -> BusyBox init -> wired DHCP -> logs config/network state
```

Phase 3 adds mode resolution and browser supervision on top of that: the image decides an effective display mode (`dashboard`/`signage`/`diagnostics`) from `/etc/talaria/display.conf`, `/data/talaria/display.conf`, and an optional server assignment endpoint, defaults fresh/unconfigured devices to the baked Talaria logo, falls back to `diagnostics` on invalid config, retries without a reboot, and supervises a WPE/Cog kiosk browser against the resolved mode (launch, relaunch on crash, stop on fallback). See [`docs/display-runtime-design.md`](docs/display-runtime-design.md).

The mode-resolution and browser-supervision shell logic is implemented and unit-tested (`scripts/test-mode-resolve.sh`, `scripts/test-browser-supervise.sh`). The WPE/Cog/Mesa Buildroot package wiring has been validated by real from-source CI builds: the defconfig resolves cleanly, WPEWebKit/Cog/Mesa compile, and the resulting image boots in QEMU. The browser path has also rendered a local HTML/CSS/font test page in a VM. `scripts/verify-browser-packages.sh` still catches an obviously wrong or renamed symbol fast, before paying the multi-hour build cost again. What's still unproven is real hardware and rendering the real Talaria dashboard/signage pages from the app/server stack. See `docs/hardware-inventory.md`.

## Repo Layout

```text
buildroot-version.txt
scripts/
  build.sh
  bootstrap-buildroot.sh
  ci-install-deps.sh
  flash-usb.sh
  package-artifacts.sh
  qemu-smoke-test.sh
  run-qemu.sh
  save-defconfig.sh
  test-mode-resolve.sh
  test-browser-supervise.sh
  test-browser-init.sh
  verify-browser-packages.sh
  verify-kernel-video-config.sh
external/
  external.desc
  Config.in
  external.mk
  configs/
    talaria_display_x86_64_defconfig
  board/
    talaria/
      display-x86_64/
        genimage-bios.cfg
        grub-bios.cfg
        linux-video.fragment
        rootfs_overlay/
        post-build.sh
        post-image.sh
docs/
  build-and-boot.md
  first-boot-test.md
  hardware-inventory.md
  display-runtime-design.md
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
- `diffutils`, `findutils`, `gawk`, `sed`
- `libelf-dev` on apt-based Linux hosts
- `wget` or `curl`
- common archive tools such as `tar`, `xz`, `gzip`, `bzip2`

Buildroot will download source packages as needed. Keep the download cache outside git.

## Buildroot Version

The pinned Buildroot version is stored in:

```text
buildroot-version.txt
```

The initial pin is `2026.05.1`, the current stable bugfix release as of this bootstrap. If browser package compatibility becomes unstable, consider moving to the Buildroot LTS series after the first successful WPE/Cog build.

The Linux kernel is pinned in the board defconfig instead of tracking Buildroot's latest kernel. The current pin is Linux `6.12.94`, a 6.12 longterm release.

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

The expected disk image is:

```text
output/images/disk.img
```

Package the boot image, manifest, checksums, and test notes with:

```sh
./scripts/package-artifacts.sh
```

GitHub Actions also builds this image on pull requests and on pushes to `main`, then uploads the packaged artifact from the workflow run. Main builds that pass the QEMU smoke test also update a rolling `dev-latest` GitHub Release (prerelease) with the current image — see [`docs/build-and-boot.md`](docs/build-and-boot.md#github-releases).

The automatic full-image workflows are path-filtered to OS build inputs:

```text
.github/workflows/
buildroot-version.txt
external/
scripts/
```

Use `workflow_dispatch` on either workflow to force a full image build for any other change.

## Defconfig Hygiene

After changing Buildroot settings with `menuconfig`, save the minimized external-tree defconfig with:

```sh
./scripts/save-defconfig.sh
```

This reloads `talaria_display_x86_64_defconfig` with the Talaria `BR2_EXTERNAL` path and writes the trimmed result back to:

```text
external/configs/talaria_display_x86_64_defconfig
```

## QEMU

On a Linux host with QEMU installed:

```sh
./scripts/run-qemu.sh
```

The QEMU runner uses IDE storage and an e1000 NIC to stay closer to old workstation hardware than a virtio-only VM.

For CI-style validation without a graphical window:

```sh
./scripts/qemu-smoke-test.sh
```

The smoke test boots `output/images/disk.img`, captures serial output to `artifacts/qemu-smoke.log`, and passes when the Phase 1 ready marker and a mode-resolution marker both appear.

CI caches Buildroot downloads plus the generated host toolchain directories under `output/host` and selected host build stamps. This is intentionally narrower than caching the whole `output/` tree so target images still rebuild from the current external tree.

## Flashing

The initial scaffold does not assume a final USB image format yet. Once the first bootable image is emitted, use:

```sh
sudo ./scripts/flash-usb.sh /dev/sdX output/images/<image>.img
```

The flashing script is intentionally defensive and requires explicit confirmation.

## First Hardware Milestone

Success for the first real milestone:

```text
Old PC boots -> shows splash -> gets DHCP -> writes /data/talaria/phase1.log -> launches assigned browser content when configured
```

Browser-stack code, mode resolution, assignment polling, and supervision are now part of the image. The next milestone is proving the same path on at least one real target workstation, then wiring the matching assignment endpoint in edge-api/workbench once those branches are current.

## Useful References

- Buildroot manual: https://buildroot.org/downloads/manual/manual.html
- Buildroot external trees: https://buildroot.org/downloads/manual/manual.html#outside-br-custom
- WPE WebKit: https://wpewebkit.org/
- BusyBox: https://busybox.net/about.html
