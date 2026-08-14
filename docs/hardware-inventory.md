# Hardware Inventory

Capture one row per candidate workstation before tuning the image.

Target fleet is deliberately wide: roughly 2004-2014 era x86_64 workstations, whatever mix of decommissioned office/shop-floor PCs is actually on hand — not a single reference machine. The build's job is to be as compatible as reasonably possible across that spread (see `linux-video.fragment` and `grub-bios.cfg`'s `vga=791`), and this table is how "reasonably possible" gets checked against reality instead of staying a guess. Every row matters more for what it rules out than what it confirms.

| ID | Model | Year | CPU | x86_64 | RAM | GPU | GPU Driver Used | NIC | BIOS/UEFI | Monitor | USB Boot | Video Result | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| display-01 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |
| candidate-hp-dx2200 | HP Compaq dx2200 Microtower | ~2006 | Celeron D 326-346 or Pentium 4 516/519K/521/524/541 (Socket 775) | **check per unit** — see note below | 2 GB max (DDR2-667, 2 slots) | ATI Radeon Xpress 200 IGP (RS480/RC410, "derived from Radeon X300") | expected `radeon` (already in `linux-video.fragment`) | not yet researched | BIOS-only | untested | untested | untested | not yet tested — spec-sheet only |

**GPU Driver Used**: which kernel driver actually bound (`i915`/`radeon`/`nouveau`/`mgag200`/`ast`/`simpledrm`/none) — check with `cat /sys/class/drm/*/device/uevent` or `dmesg | grep -i drm` on the target console.

**Video Result**: whether `vga=791` gave a usable framebuffer, whether a browser (once the stack builds) actually renders, or whether the device landed on the `TALARIA_BROWSER_GIVING_UP` visible-failure path (see `docs/display-runtime-design.md#browser-phase`). A device that never gets real video but still boots to a working diagnostics console is a partial pass, not a failure — record it as such.

## Notes To Capture

- BIOS key and boot-order behavior.
- Whether USB boot persists after power loss.
- Wired NIC driver name from Linux.
- GPU driver name from Linux, and whether it needed the `simpledrm`/`vesafb` fallback rather than a chipset-specific driver.
- Native monitor resolution, and whether `vga=791` matched it or forced a different mode.
- Boot time from power button to userspace.
- Any firmware warnings.

## Known Candidate: HP Compaq dx2200

Researched from public spec sheets, not yet hands-on tested — treat as "worth trying," not "confirmed working." If units are on hand, promote this to a real numbered row above once tested.

- **CPU / x86_64 eligibility is per-unit, not guaranteed by model name.** HP sold the dx2200 with a mix of processors: Celeron D 326/331/336/346 all shipped with EM64T (Intel's 64-bit extension) enabled — confirmed. The Pentium 4 519K also has EM64T enabled despite the "K" suffix looking like a cost-reduced part. Not every Pentium 4 5xx-series option in this line is guaranteed 64-bit, though (the 516 in particular is unconfirmed either way). Since this image is x86_64-only (no 32-bit fallback), **check every physical unit individually** before assuming it'll boot the image at all:
  ```sh
  grep -o lm /proc/cpuinfo | head -1   # prints "lm" if the CPU supports long mode (64-bit); empty if not
  ```
  This is exactly the "32-bit-only machines may not be worth supporting" risk called out in the broader Talaria Display OS plan — the dx2200 line is a real-world example of why that risk is per-unit, not per-model.
- **GPU**: the ATI Radeon Xpress 200 integrated graphics (RS480/RC410 chipset family) is handled by Linux's legacy `radeon` DRM driver, not `amdgpu` — that's `CONFIG_DRM_RADEON`, already enabled in `linux-video.fragment`. KMS support for this specific IGP had some rough edges in early KMS-era kernels (~2010-2011) but should be solid on the pinned 6.12 kernel. Being derived from the R300 generation (pre-UVD), it shouldn't need external firmware blobs for basic modesetting, unlike some later AMD/Intel GPUs.
- **RAM ceiling**: 2 GB max (DDR2-667, non-ECC). Tight but workable for a kiosk browser — worth watching during real testing given WPEWebKit's footprint, more than most other constraints here.
- **NIC**: not yet researched. Confirm chipset and mainline Linux driver before assuming wired DHCP "just works" the way it has on other Phase 1 test units.

## Decision Rule

Do not optimize for the newest/easiest workstation first. The proof of concept only matters if the oldest realistic target can boot, network, and display reliably. For the video/browser stack specifically: a config choice that only works on one nice machine in the pile isn't done — the point is graceful degradation (working diagnostics console at minimum) across whatever the fleet actually turns out to be, not a single golden machine.
