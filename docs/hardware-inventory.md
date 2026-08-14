# Hardware Inventory

Capture one row per candidate workstation before tuning the image.

Target fleet is deliberately wide: roughly 2004-2014 era x86_64 workstations, whatever mix of decommissioned office/shop-floor PCs is actually on hand — not a single reference machine. The build's job is to be as compatible as reasonably possible across that spread (see `linux-video.fragment` and `grub-bios.cfg`'s `vga=791`), and this table is how "reasonably possible" gets checked against reality instead of staying a guess. Every row matters more for what it rules out than what it confirms.

| ID | Model | Year | CPU | x86_64 | RAM | GPU | GPU Driver Used | NIC | BIOS/UEFI | Monitor | USB Boot | Video Result | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| display-01 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

Rows above are for units actually in hand and tested. [Researched Candidates](#researched-candidates-not-yet-hands-on-tested) below tracks spec-sheet research on models worth sourcing but not yet tested — promote a candidate to a real row here once a unit is tested.

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

## Researched Candidates (Not Yet Hands-On Tested)

Spec-sheet research on models worth sourcing, not confirmed working — "worth trying," not "confirmed." Promote a row to the real fleet table above once an actual unit is tested. `x86_64` status marked "per-unit" means the model shipped with a mix of processors and this image (x86_64-only, no 32-bit fallback) needs a check on every physical unit, not an assumption from the model name:

```sh
grep -o lm /proc/cpuinfo | head -1   # prints "lm" if the CPU supports long mode (64-bit); empty if not
```

| Model | Era | x86_64 | Chipset / GPU | Expected Driver | RAM Cap | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| HP Compaq dx2200 Microtower | ~2006 | per-unit — Celeron D 326-346 confirmed, P4 519K confirmed, P4 516 unconfirmed | ATI Radeon Xpress 200 (RS480/RC410) | `radeon` | 2 GB | Business line. NIC unresearched. |
| Dell OptiPlex GX620 | 2005 | per-unit — same P4/Pentium D/Celeron D mix as the dx2200 | Intel 945G, onboard GMA950 (or optional discrete ATI Radeon X600SE) | `i915` onboard, `radeon` if the discrete card is populated | not confirmed | Business line. Prefer confirming onboard GMA950 over the optional discrete card — fewer unknowns. |
| Dell OptiPlex 755 | 2007-2008 | **yes, uniformly** — Core 2 Duo (e.g. E6550) has no 32-bit-only variants | Intel Q35, onboard GMA3100 | `i915` | 4 GB (8 GB max) | Business line. Meaningfully safer bet than any Pentium 4/Celeron D-era machine — no per-unit CPU check needed. |
| Dell OptiPlex 760 | 2008-2009 | **yes, uniformly** — Core 2 Duo/Quad | Intel Q45, onboard GMA4500 (or optional discrete ATI HD3450/3470, Nvidia 9300GE) | `i915` onboard | 8 GB max | Business line. Best RAM headroom of any candidate here — most WPEWebKit-friendly. Newest/safest option so far. |
| Dell Dimension E520 | 2006 | per-unit — Celeron through Core 2 Duo options | Intel G965, onboard GMA X3000 (or discrete ATI X1300 Pro, Nvidia GeForce 7300LE) | `i915` onboard | not confirmed | Consumer line, not business — less representative of the shop-floor reuse case than the OptiPlex models. |
| Dell Dimension E521 | ~2006 | AMD Athlon 64 X2/Athlon 64/Sempron (Socket AM2) — AMD64 was 64-bit-native for these, less ambiguity than the Intel P4 era | AMD chipset, onboard Nvidia GeForce 6150 LE | `nouveau` | up to 4 GB | Consumer line, AMD-based. First real candidate matching our `nouveau` inclusion, which was otherwise speculative. |

Two things fall out of this pass: Intel's onboard graphics (GMA950/3100/X3000/4500, all `i915`) show up across nearly every model here and have by far the most mature, consistent mainline Linux driver of any vendor in this era — worth weighting selection toward Intel-graphics units when there's a choice, even though `radeon`/`nouveau` coverage exists as a fallback. And the Core 2 Duo generation (OptiPlex 755/760, roughly 2007+) removes the 64-bit-eligibility guesswork entirely, unlike every Pentium 4/Celeron D/early-Athlon-era machine above — if minimizing unknowns matters more than maximizing "how old can we go," that's the era to prioritize sourcing from.

## Decision Rule

Do not optimize for the newest/easiest workstation first. The proof of concept only matters if the oldest realistic target can boot, network, and display reliably. For the video/browser stack specifically: a config choice that only works on one nice machine in the pile isn't done — the point is graceful degradation (working diagnostics console at minimum) across whatever the fleet actually turns out to be, not a single golden machine.
