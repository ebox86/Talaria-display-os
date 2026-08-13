# Hardware Inventory

Capture one row per candidate workstation before tuning the image.

| ID | Model | Year | CPU | x86_64 | RAM | GPU | NIC | BIOS/UEFI | Monitor | USB Boot | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| display-01 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD |

## Notes To Capture

- BIOS key and boot-order behavior.
- Whether USB boot persists after power loss.
- Wired NIC driver name from Linux.
- GPU driver name from Linux.
- Native monitor resolution.
- Boot time from power button to userspace.
- Any firmware warnings.

## Decision Rule

Do not optimize for the newest/easiest workstation first. The proof of concept only matters if the oldest realistic target can boot, network, and display reliably.
