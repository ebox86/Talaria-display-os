# Build And Boot

This is the build path for a BIOS-bootable Talaria Display OS disk image, covering Phase 1 bring-up plus Phase 3 mode resolution and browser supervision.

## Goal

Create and boot:

```text
output/images/disk.img
```

The image should:

- boot with GRUB BIOS
- show a Talaria console splash on `tty1`
- mount root from partition 1
- mount persistent `/data` from partition 2 labeled `TALARIA_DATA`
- acquire wired DHCP
- write diagnostic logs under `/data/talaria`
- resolve an effective display mode (`dashboard`/`signage`/`diagnostics`) from `/etc/talaria/display.conf` and `/data/talaria/display.conf`, falling back to `diagnostics` on any invalid or unreachable config
- supervise a WPE/Cog kiosk browser against the resolved mode, relaunching on crash or on a URL change, stopping it entirely in `diagnostics`

See [`display-runtime-design.md`](display-runtime-design.md) for the full mode/fallback/browser-supervision design.

## Build Host

Use a Linux build host or VM. macOS is fine for editing the repo, but Buildroot builds and USB flashing should happen on Linux.

On apt-based Linux hosts, install `libelf-dev` before building. The x86_64 Linux kernel build uses host-side `objtool`, which needs `gelf.h` from libelf.

CI installs the common Buildroot host tools explicitly, including `diffutils`, `findutils`, `gawk`, `sed`, `curl`, and `wget`, plus a best-effort set of extras for the WPEWebKit/Cog/Mesa build (`cmake`, `ninja-build`, `bison`, `flex`, `gperf`, `ruby`, and others — see `scripts/ci-install-deps.sh`). Buildroot builds most of its own host tooling from source, so this list may still be missing something the first time it actually runs; a build failing on a missing host command is a one-line fix to that script.

The rootfs image size (`BR2_TARGET_ROOTFS_EXT2_SIZE`) is `1536M` to leave room for WPEWebKit/Mesa/ICU, up from `256M` for the Phase 1 console-only image.

## Kernel Pin

The board defconfig pins Linux to `6.12.94` instead of Buildroot's moving latest kernel option. It also sets the toolchain kernel headers to use the same kernel source and declares the headers as the `6.12.x` series. Keep these pinned unless we intentionally validate a kernel update on target hardware.

A config fragment (`board/talaria/display-x86_64/linux-video.fragment`, layered on top via `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES`) adds broad DRM/framebuffer driver coverage for the wide range of target hardware — see [`display-runtime-design.md`](display-runtime-design.md#target-hardware). It's best-effort; `scripts/build.sh` runs `scripts/verify-kernel-video-config.sh` right after `linux-configure` to catch a wrong symbol before the full build.

## Build

```sh
./scripts/bootstrap-buildroot.sh
./scripts/build.sh
```

Build output:

```text
output/images/disk.img
output/images/boot.img
output/images/grub.img
output/images/talaria-display-os-manifest.txt
output/images/SHA256SUMS
```

To create the same downloadable bundle produced by GitHub Actions:

```sh
./scripts/package-artifacts.sh
```

Packaged output:

```text
artifacts/talaria-display-os-<buildroot-version>-<git-sha>.tar.gz
```

The bundle contains the renamed boot image, checksums, build manifest, and test notes.

## Saving Defconfig

After changing Buildroot settings through `menuconfig`, save the minimized external-tree defconfig with:

```sh
./scripts/save-defconfig.sh
```

The script writes back to `external/configs/talaria_display_x86_64_defconfig`.

## GitHub Actions Artifacts

Pull requests run `PR Build` and upload a 7-day test artifact named:

```text
talaria-display-os-pr-<run-number>
```

Pushes to `main` run `Main Build` and upload a 30-day artifact named:

```text
talaria-display-os-main-<run-number>
```

Download and extract the artifact, then use the included image with QEMU or `scripts/flash-usb.sh`.

## GitHub Releases

Every `Main Build` run that passes the QEMU smoke test replaces a single rolling GitHub Release, tagged `dev-latest`, with the current packaged bundle (image, checksums, manifest, docs) attached as a release asset. This exists mainly so a downloadable image has a permanent, stable URL — useful for pulling a disk image into a VM (Hyper-V, UTM, VirtualBox, whatever) without needing to be signed into the Actions UI or race a 30-day artifact expiry.

It's one release that gets replaced each time, not a new tag per build — a fresh release per commit gets noisy fast and isn't the point; the point is "give me something to boot right now." For a specific past build within the last 30 days, use that run's `talaria-display-os-main-<run-number>` workflow artifact instead (includes `qemu-smoke.log`).

`dev-latest` is marked prerelease and is an automatic dev snapshot, not a curated versioned release — the release existing means the image booted in QEMU, not that the browser stack built successfully. Check that specific run's build log before assuming more than "it boots to whatever mode it resolved, including possibly `diagnostics` if WPE/Cog didn't build." A build that fails the smoke test does not touch the release; the 30-day artifact is still uploaded for those to debug from.

The automatic PR and main workflows are path-filtered to Buildroot inputs, board files, scripts, and workflow files. Use the workflow's manual `workflow_dispatch` button when a docs-only or planning-only change still needs a full image build.

CI caches source downloads and the generated Buildroot host toolchain cache:

```text
dl/
.build/buildroot-<version>.tar.xz
output/host
output/build/host-*
output/build/toolchain-*
output/build/linux-headers-*
```

The cache key includes the Buildroot version, external tree, and build scripts. The full target output is intentionally not cached.

## QEMU Smoke Test

Install QEMU on the Linux build host, then run:

```sh
./scripts/run-qemu.sh
```

The QEMU runner intentionally uses IDE storage and an e1000 NIC instead of virtio so device naming and drivers are closer to old desktop PCs.

For a headless boot check matching CI:

```sh
./scripts/qemu-smoke-test.sh
```

The smoke test captures serial console output to:

```text
artifacts/qemu-smoke.log
```

It passes when the boot log contains `TALARIA_PHASE1_READY` and either `TALARIA_MODE_RESOLVED` or `TALARIA_MODE_FALLBACK`.

Expected target logs:

```text
/data/talaria/data-mount.log
/data/talaria/network-wait.log
/data/talaria/phase1.log
/data/talaria/display-mode.log
```

To check the mode-resolution and browser-supervision logic itself (validation, fallback rules, launch/restart/crash-recovery) without a Linux build host, Buildroot, or QEMU:

```sh
./scripts/test-mode-resolve.sh
./scripts/test-browser-supervise.sh
```

The first runs `usr/bin/talaria-resolve-mode` directly against temp config files for each mode/fallback case; the second runs `usr/bin/talaria-browser-supervise` against a fake browser stub. Neither validates init sequencing, actual boot behavior, or the real WPE/Cog binary — that still needs the QEMU smoke test above and, eventually, real hardware.

Before a full image build, `scripts/build.sh` also runs `scripts/verify-browser-packages.sh`, which checks that the WPE/Cog/Mesa Kconfig symbols in the defconfig actually resolved to `y` in the generated `.config`. Those symbol names are best-effort (not verified against a real Buildroot 2026.05.1 checkout) — this check exists so a wrong or renamed one fails in seconds, before the multi-hour WPEWebKit build, rather than after.

## Hardware Flash

Identify the USB device carefully:

```sh
lsblk
```

Flash:

```sh
sudo ./scripts/flash-usb.sh /dev/sdX output/images/disk.img
```

The script asks for `YES` before writing.

## First Hardware Pass Criteria

- BIOS boots USB without manual intervention after boot order is set.
- Talaria splash appears on the primary console.
- Wired DHCP comes up.
- `/data/talaria/phase1.log` exists.
- `/data/talaria/phase1.log` persists after reboot.
- The Talaria server can be pinged by IP or hostname.

## Known Constraints

- This pass is BIOS-first, not UEFI.
- Root is currently configured as `/dev/sda1`.
- Persistent data is currently expected at `/dev/sda2`, with fallback probes for older/QEMU names.
- The WPE/Cog browser stack has not yet completed a real Buildroot build. Mode resolution and browser supervision are implemented and unit-tested, but the actual `BR2_PACKAGE_WPEWEBKIT`/`COG`/`MESA3D` Kconfig wiring is best-effort and unverified until it runs on a real Buildroot checkout — see [`display-runtime-design.md`](display-runtime-design.md#browser-phase).
