# Hardware Inventory

Capture one row per candidate workstation before tuning the image.

Target fleet is deliberately wide: roughly 2004-2014 era x86_64 workstations, whatever mix of decommissioned office/shop-floor PCs is actually on hand — not a single reference machine. The build's job is to be as compatible as reasonably possible across that spread (see `linux-video.fragment` and `grub-bios.cfg`'s `vga=791`), and this table is how "reasonably possible" gets checked against reality instead of staying a guess. Every row matters more for what it rules out than what it confirms.

| ID | Model | Year | CPU | x86_64 | RAM | GPU | GPU Driver Used | NIC | BIOS/UEFI | Monitor | USB Boot | Video Result | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| display-01 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

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

## Decision Rule

Do not optimize for the newest/easiest workstation first. The proof of concept only matters if the oldest realistic target can boot, network, and display reliably. For the video/browser stack specifically: a config choice that only works on one nice machine in the pile isn't done — the point is graceful degradation (working diagnostics console at minimum) across whatever the fleet actually turns out to be, not a single golden machine.
