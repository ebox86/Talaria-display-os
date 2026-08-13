# Build And Boot

This is the Phase 1 build path for a BIOS-bootable Talaria Dashboard OS disk image.

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

## Build Host

Use a Linux build host or VM. macOS is fine for editing the repo, but Buildroot builds and USB flashing should happen on Linux.

## Build

```sh
./scripts/bootstrap-buildroot.sh
./scripts/build.sh
```

Build output:

```text
output/images/disk.img
output/images/talaria-dashboard-os-manifest.txt
output/images/SHA256SUMS
```

To create the same downloadable bundle produced by GitHub Actions:

```sh
./scripts/package-artifacts.sh
```

Packaged output:

```text
artifacts/talaria-dashboard-os-<buildroot-version>-<git-sha>.tar.gz
```

The bundle contains the renamed boot image, checksums, build manifest, and test notes.

## GitHub Actions Artifacts

Pull requests run `PR Build` and upload a 7-day test artifact named:

```text
talaria-dashboard-os-pr-<run-number>
```

Pushes to `main` run `Main Build` and upload a 30-day artifact named:

```text
talaria-dashboard-os-main-<run-number>
```

Download and extract the artifact, then use the included image with QEMU or `scripts/flash-usb.sh`.

## QEMU Smoke Test

Install QEMU on the Linux build host, then run:

```sh
./scripts/run-qemu.sh
```

The QEMU runner intentionally uses IDE storage and an e1000 NIC instead of virtio so device naming and drivers are closer to old desktop PCs.

Expected target logs:

```text
/data/talaria/data-mount.log
/data/talaria/network-wait.log
/data/talaria/phase1.log
```

The current splash is console-based and intentionally does not require a framebuffer image viewer or browser stack. Later WPE/Cog work can replace it by launching the kiosk browser over the same display.

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
- No WPE WebKit/Cog browser stack is included yet.
