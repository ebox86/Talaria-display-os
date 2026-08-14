# Display Runtime Design

Talaria Display OS should treat the screen as a managed Talaria endpoint, not as a dashboard-only device. The same OS image should support production dashboards, digital signage, and local diagnostics without rebuilding the image per use case, and it should degrade to a safe local state whenever the server or configured content is unavailable.

Phase 1 (console bring-up, networking, `/data` mount, diagnostics logging), Phase 3's mode resolution, and Phase 3's browser supervision are all implemented under `external/board/talaria/display-x86_64/rootfs_overlay/`. The one piece that's genuinely unproven is the WPE/Cog Buildroot package wiring itself (see [Browser Phase](#browser-phase)) — it hasn't been validated against a real Buildroot build yet.

## Target Hardware

The fleet is deliberately wide, not a single reference machine: roughly 2004-2014-era x86_64 workstations, whatever decommissioned office/shop-floor PCs are actually on hand. "As compatible as reasonably possible across that spread" is the actual design constraint, not "works on the dev's test box" — see `docs/hardware-inventory.md`, which tracks per-device results as they come in rather than assuming one config fits all of them. Concretely, this shapes:

- **Software GL by default** ([Browser Phase](#browser-phase)) instead of betting on any one GPU vendor's driver working.
- **A kernel config fragment** (`board/talaria/display-x86_64/linux-video.fragment`) with broad DRM driver coverage for GPUs likely to show up in that era, plus `CONFIG_DRM_SIMPLEDRM`/`CONFIG_FB_VESA` as a generic fallback for whatever isn't specifically covered.
- **A GRUB `vga=791` boot parameter** ([`grub-bios.cfg`](../external/board/talaria/display-x86_64/grub-bios.cfg)) so even hardware with no chipset-specific driver gets *some* usable video mode for simpledrm to pick up. VBE BIOS behavior varies across this much hardware; this is a reasonable default, not a guarantee — real per-machine results belong in `hardware-inventory.md`.
- **A visible give-up signal** when the browser genuinely can't render on a given machine ([Browser Phase](#browser-phase)), instead of a silent crash loop behind a stale splash — expect a real fraction of this fleet to hit that path, and the device should still be a working diagnostics appliance when it does.

## Goals

- Boot unattended on old x86_64 workstations.
- Persist identity and runtime configuration under `/data/talaria`.
- Let the Talaria server eventually decide what a display endpoint should render.
- Support dashboard and signage modes through the same browser/runtime stack.
- Fall back to local diagnostics whenever the server, the configured mode, or the configured content is unavailable — never a blank screen, a crash loop, or a silent hang.
- Let an operator fix a misconfigured device by editing `/data/talaria/display.conf` and letting the existing retry loop pick it up, without reflashing or rebuilding the image.

## Runtime Config

Two files, same field names, two roles:

```text
/etc/talaria/display.conf      baked into the image; ships safe defaults
/data/talaria/display.conf     writable override on the persistent data partition
```

`/etc/talaria/display.conf` is read first; `/data/talaria/display.conf` is read second and wins field-by-field when present. This is already how `S60talaria-phase1` sources both files today, and mode-resolution logic should keep that precedence rather than replacing it. A device with no override file at all still boots to a defined state using the baked-in defaults — it does not fail to start.

### Fields

| Field | Required | Default (`/etc`) | Notes |
| --- | --- | --- | --- |
| `TALARIA_SERVER_HOST` | no | `talaria.local` | Hostname or IP used for reachability checks and, later, the server contract calls. |
| `TALARIA_DISPLAY_MODE` | no | `dashboard` | One of `dashboard`, `signage`, `diagnostics`. Any other value is treated as invalid — see [Fallback Behavior](#fallback-behavior). |
| `TALARIA_DISPLAY_URL` | mode-dependent | `http://talaria.local:5173/dashboard/` | Direct boot target for `dashboard`/`signage` modes until the server contract exists. Ignored in `diagnostics` mode. |
| `TALARIA_DEVICE_ID` | no | `unconfigured` | Identity used for future server calls and for labeling logs/diagnostics screens. A device shipped with `unconfigured` should still boot and run diagnostics, not fail closed. |

Unrecognized fields in either file should be preserved by shell sourcing (harmless) but are not defined behavior — a future config parser is free to ignore or warn on them rather than fail.

### Example override

```sh
mkdir -p /data/talaria
cat > /data/talaria/display.conf <<'EOF'
TALARIA_SERVER_HOST=192.168.1.50
TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=http://192.168.1.50:5173/dashboard/
TALARIA_DEVICE_ID=display-01
EOF
```

This is the same pattern already used in [`first-boot-test.md`](first-boot-test.md) to work around unresolvable hostnames during bring-up; it is also the intended day-to-day way to assign a device its identity and mode before the server contract exists.

## Display Modes

| Mode | Purpose | Needs `TALARIA_DISPLAY_URL` | Needs network | Content owner |
| --- | --- | --- | --- | --- |
| `dashboard` | Production status boards, delivery boards, KPI views, other operational screens. | yes | yes | Talaria server / dashboard app |
| `signage` | Talaria-managed static or animated digital signage — menu boards, promo screens, wayfinding. | yes | yes | Talaria server (content assignment, not the OS image) |
| `diagnostics` | Local status and recovery screen. Also the automatic fallback target for every other mode. | no | no | Display OS itself |

`dashboard` and `signage` are rendering-target distinctions, not different software stacks: both load a server-assigned URL in the kiosk browser. The difference is what's expected to be at that URL (an interactive-feeling operational view vs. unattended promotional content) and, later, what retry/refresh policy the server hands back for each. Nothing about the browser launcher should need to branch on `dashboard` vs. `signage` beyond passing through the configured URL and refresh policy.

`diagnostics` is the odd one out: it is rendered locally, requires nothing from the network or the server, and must always be reachable even if `/data` failed to mount, DHCP never came up, or the config file is empty or corrupt. The Phase 1 console splash (`usr/bin/talaria-splash`) is already this mode's minimal form today. A later phase can replace it with a browser-rendered diagnostics page without changing the contract: diagnostics never depends on external content.

## Mode Resolution

Mode resolution slots in after the existing Phase 1 init stages, before any browser is launched:

```text
S20talaria-data           mount /data, log result
S50talaria-network-wait   wait up to 30s for a default route, log result
S60talaria-phase1         source config, write phase1.log, diagnostics splash
S70talaria-mode-resolve   decide effective mode, retry loop, write mode-state.conf
S80talaria-browser        supervise the browser against mode-state.conf
```

`S70talaria-mode-resolve` is a thin init wrapper (`etc/init.d/S70talaria-mode-resolve`) around a single-shot resolver (`usr/bin/talaria-resolve-mode`). The wrapper runs the resolver once at `start`, then backgrounds a loop that re-runs it every `TALARIA_MODE_RESOLVE_INTERVAL` seconds (default 15). The resolver itself is pure enough to unit-test on the build host — its config paths and reachability probe are environment-overridable, and `scripts/test-mode-resolve.sh` exercises the cases below without needing Buildroot or QEMU.

Resolution logic, in order (each retry cycle, from scratch):

1. Source `/etc/talaria/display.conf`, then `/data/talaria/display.conf` if present, per the precedence above.
2. If `TALARIA_DISPLAY_MODE` is not one of `dashboard`, `signage`, `diagnostics` — fall back to `diagnostics`.
3. If the resolved mode is `dashboard` or `signage` and `TALARIA_DISPLAY_URL` is unset or not a well-formed `http(s)://` URL — fall back to `diagnostics`.
4. If the resolved mode is `dashboard` or `signage`, probe reachability of `TALARIA_SERVER_HOST` with `ping -c 1 -W 2` — if unreachable, hold in `diagnostics` and keep retrying rather than launching a browser at a dead URL.
5. Otherwise, resolve to the configured mode and hand it to the browser supervisor via the state file below.

This keeps `diagnostics` as both a first-class mode an operator can pin a device to, and the automatic result of every failure path above. Each resolution — success or fallback — is appended to `/data/talaria/display-mode.log` and echoed to the console as `TALARIA_MODE_RESOLVED mode=<mode> url=<url>` or `TALARIA_MODE_FALLBACK reason="<reason>" configured_mode=<mode>`, which `scripts/qemu-smoke-test.sh` checks for.

### Handoff to the browser: `mode-state.conf`

Rather than have the browser supervisor re-implement the fallback rules above, the resolver also writes a compact, shell-sourceable state file to `/run/talaria/mode-state.conf` on every cycle:

```sh
EFFECTIVE_MODE=dashboard
DISPLAY_URL=http://talaria.local:5173/dashboard/
FALLBACK_REASON=""
DEVICE_ID=display-01
RESOLVED_AT="Fri Aug 14 02:00:00 EDT 2026"
```

`DISPLAY_URL` is always empty whenever `EFFECTIVE_MODE` is `diagnostics` or a fallback fired, even if a URL happens to be configured — the supervisor never has to re-derive "should I actually trust this URL," it just checks whether one is present.

## Fallback Behavior

Fallback to `diagnostics` is triggered by any of:

- `/data` partition not mounted (see `S20talaria-data`'s existing failure path — it already continues rather than halting).
- No default route within the existing 30s network-wait window.
- `/data/talaria/display.conf` present but unparseable, or absent along with a missing/invalid `/etc/talaria/display.conf` default.
- `TALARIA_DISPLAY_MODE` set to anything other than `dashboard`, `signage`, or `diagnostics`.
- `TALARIA_DISPLAY_URL` unset, malformed, or unreachable for `dashboard`/`signage`.
- The browser process crashes or exits unexpectedly (`usr/bin/talaria-browser-supervise` detects this and relaunches — see [Browser Phase](#browser-phase)).

While in fallback, the device:

- Shows a diagnostics screen (`talaria-splash diagnostics "Fallback: <reason>"`) with the specific reason fallback was triggered — not just "error."
- Logs to `/data/talaria/display-mode.log` in the same append-friendly style as `phase1.log`, `data-mount.log`, and `network-wait.log`, so a technician can pull logs off the USB stick without a live session.
- Retries every `TALARIA_MODE_RESOLVE_INTERVAL` seconds (default 15) without requiring a reboot. Each retry re-reads both config files from scratch, so dropping a corrected `/data/talaria/display.conf` is enough to recover on its own within one interval — no manual restart, no reflash. (`S70talaria-mode-resolve restart` still works too, matching the manual-restart workaround `first-boot-test.md` already documents for Phase 1.)
- Never hard-fails the boot. A device that can never reach its server still runs as a working diagnostics appliance indefinitely, not a device that stops responding.

Backoff is intentionally flat (fixed interval, not exponential) — a display endpoint recovering from a config fix or a flaky link should come back quickly, and there's no external service being hammered by a `ping` every 15s.

## Server Contract

Not implemented yet. Once it exists, the OS calls the Talaria server with `TALARIA_DEVICE_ID` and receives:

- assigned mode (`dashboard` / `signage` / `diagnostics`)
- content URL or playlist URL
- refresh/retry policy
- display name/location
- health reporting interval
- emergency override content, if any

A server-assigned mode should follow the same fallback rules as a locally configured one: an invalid or unreachable assignment falls back to `diagnostics` locally rather than trusting the server response blindly. Until the contract exists, `TALARIA_DISPLAY_URL` in `display.conf` is the direct boot target described above.

## Browser Phase

`S80talaria-browser` backgrounds `usr/bin/talaria-browser-supervise`, which polls `/run/talaria/mode-state.conf` (default every `TALARIA_BROWSER_POLL_INTERVAL`, 5s) and reconciles the running browser process against it:

- `EFFECTIVE_MODE` is `dashboard` or `signage` and `DISPLAY_URL` differs from what's currently running → stop the old process (if any) and launch the browser against the new URL.
- `EFFECTIVE_MODE` is `diagnostics` (explicit or fallback) → stop the browser if one is running. Diagnostics itself stays the console splash from `S70`/`talaria-resolve-mode`, not a browser page — see [Diagnostics stays console-only](#diagnostics-stays-console-only) below.
- The running browser process disappears unexpectedly → logged as `TALARIA_BROWSER_CRASHED` and relaunched against the same target, subject to the backoff below.

Console markers: `TALARIA_BROWSER_LAUNCH url=<url> pid=<pid>`, `TALARIA_BROWSER_STOPPED mode=<mode>`, `TALARIA_BROWSER_CRASHED target=<url>`. Crash detection deliberately does not use `kill -0` on the browser's pid — a child that exited but hasn't been reaped is a zombie, and `kill -0` on a zombie still succeeds. Each browser is launched inside a small monitor subshell that `wait`s on its own child (the only process allowed to reap it) and drops an exit-marker file when it's gone; the supervisor checks that marker instead.

### Giving up visibly

Given the hardware spread ([Target Hardware](#target-hardware)), some machines will never successfully render — bad or missing DRM driver, an unsupported mode, whatever. The supervisor tracks consecutive crashes against the same target (`TALARIA_BROWSER_MAX_CRASHES`, default 3) and, once that threshold hits, logs `TALARIA_BROWSER_GIVING_UP target=<url> attempts=<n>` once and calls `talaria-splash diagnostics "Browser unavailable after <n> attempts: <url>"` — so the operator sees an explicit failure state instead of a stale "ready" splash sitting over a browser that's silently crash-looping underneath. It keeps retrying afterward (a flaky driver might still recover) rather than giving up permanently; if the browser then stays up for `TALARIA_BROWSER_STABLE_CYCLES` (default 3) consecutive poll cycles, the crash count resets and the give-up signal can fire again later if it degrades again. A target change (new URL, or falling back to diagnostics) also resets the count — a fresh target gets a fresh chance.

Relaunches also back off: each crash sets `backoff_until = now + min(TALARIA_BROWSER_BACKOFF_BASE * 2^(crash_count-1), TALARIA_BROWSER_BACKOFF_MAX)` (defaults 5s base, 60s cap — so 5s, 10s, 20s, 40s, 60s, 60s, ...), and the supervisor won't relaunch that target until then. This only gates *relaunching the same crashing target* — it never delays noticing a mode or target change, so a config fix or a server reassignment still takes effect within one poll cycle even while the previous target is deep in backoff. Without this, a permanently-broken target would relaunch and immediately crash every single poll cycle, indefinitely, which is wasted CPU on hardware that's already struggling.

The browser command itself is a plain Cog invocation against WPE's DRM/KMS platform backend — no X11, no Wayland compositor — rendering with Mesa's software GL (llvmpipe) by default:

- **DRM/KMS, not X11/Wayland**: consistent with this image staying a minimal appliance runtime; nothing else in it runs a display server.
- **Software rendering by default**: target hardware GPUs are unknown (`docs/hardware-inventory.md` is still all TBD), and there's no way to validate hardware-accelerated GL in GitHub-hosted CI runners or the QEMU smoke test anyway. Hardware acceleration is a per-device optimization for later, once real target GPUs are known — not today's default.

`usr/bin/talaria-browser-supervise` is testable the same way the resolver is: the browser command, poll interval, and state/console paths are all environment-overridable, and `scripts/test-browser-supervise.sh` exercises launch/stop/URL-change/crash-recovery/give-up/backoff against a fake browser stub without needing WPE/Cog installed (6 scenarios).

### Diagnostics stays console-only

Decided, not open: `diagnostics` is always the console splash (`talaria-splash`), never a browser-rendered page, even once the browser stack works. The whole point of diagnostics is being the fallback for when something else is broken — the network, the config, the server, or the browser itself. A diagnostics page that depended on the browser stack could fail for the same reason the thing it's diagnosing failed, taking down the one state that's supposed to always be reachable. The console splash has no such dependency: it only needs a TTY, which is the earliest, least-likely-to-fail thing this image has.

### Single output only

Multi-monitor is out of scope, not an open question. This image is a single-purpose kiosk appliance — one device, one screen, one URL — matching the actual product shape (the broader Talaria Display OS proof-of-concept plan describes a single full-screen dashboard, not a multi-screen layout). Cog/WPE renders to whatever the DRM backend picks as its primary/first output; a machine with multiple connected outputs gets one of them, not a defined "primary" selection policy. Revisit only if a real deployment scenario actually needs it — nothing about the mode-resolution or supervision design would need to change to add it later, since both are already indifferent to how many outputs exist.

**What's unproven:** the Buildroot package selections themselves (`external/configs/talaria_display_x86_64_defconfig`) and the kernel video fragment (`board/talaria/display-x86_64/linux-video.fragment`) are best-effort attempts at the `BR2_PACKAGE_WPEWEBKIT`/`COG`/`MESA3D`/DRM and `CONFIG_DRM_*`/`CONFIG_FB_*` symbol names — not verified against an actual Buildroot 2026.05.1 checkout or kernel 6.12 tree, since no Linux host was available while writing this. `scripts/verify-browser-packages.sh` and `scripts/verify-kernel-video-config.sh` (both wired into `scripts/build.sh`) check the *resolved* config for these exact symbols right after configuring, so a wrong or renamed symbol fails in seconds/minutes instead of after a multi-hour WPEWebKit build — but neither can catch every possible way a from-source build could fail, or whether `vga=791` actually works on any given machine. Treat the first real Buildroot run and the first real hardware pass as the actual test of this section, not this doc.

## Open Questions

Three of the original five items here got resolved instead of staying open — see [Diagnostics stays console-only](#diagnostics-stays-console-only), [Single output only](#single-output-only), and the backoff paragraph under [Giving up visibly](#giving-up-visibly). What's left is genuinely blocked on things outside this repo, or on data this repo can't generate by itself:

- **Signage playlist format**, and how it differs from a single dashboard URL — blocked on the server contract, which doesn't exist yet. This is Talaria server/app design work, not display-os work; a reasonable strawman once that's underway is that `signage` gets a `DISPLAY_URL` pointing at a server-rendered playlist page (so the display endpoint still just loads one URL, the same as today) rather than the display OS itself understanding a playlist format — keeps `talaria-browser-supervise` from needing to know anything mode-specific.
- **Health reporting transport and cadence back to the Talaria server** — also blocked on the server contract (device registration, last-seen, per the broader Talaria Display OS plan's "potential server-side additions"). Also app/server-side work, not display-os work.
- **Whether/when to move off software GL** — blocked on real data, not a design decision: `docs/hardware-inventory.md` needs actual GPU/driver results from real machines before there's anything to decide. Revisit once that table has rows.

## Future Platforms (Not This Image)

Deliberately out of scope for the current `talaria_display_x86_64_defconfig`, tracked here so the ambition isn't lost, not because it's forgotten:

- **Minimal/thin-client flavor**: old x86/x86_64 thin clients (HP t5xxx, Dell/Wyse) are architecturally the same platform as everything in `hardware-inventory.md`, but with RAM and flash an order of magnitude tighter than this image assumes (some as low as 512 MB RAM / 1 GB flash total, vs. this image's 1536M rootfs alone). Supporting that class for real means a genuinely smaller build variant — fewer packages, smaller rootfs, possibly a reduced driver set — not a defconfig tweak to the existing one. A second, separate defconfig (e.g. `talaria_display_x86_64_thin_defconfig`) is the likely shape, sharing the external tree and rootfs overlay scripts but not the package list.
- **ARM (Raspberry Pi and similar)**: a genuinely separate Buildroot target architecture, not a variant of this one — different bootloader (Pi firmware/`config.txt`, no BIOS/GRUB), different kernel/device-tree story, a different GPU driver entirely (VideoCore/V3D via the `vc4`/`v3d` Mesa drivers, none of which overlap with anything in `linux-video.fragment`), and its own CI job. Deliberately sequenced after the x86_64 browser stack has had at least one real build/boot, so this repo isn't carrying two simultaneously-unverified platforms at once — see [What's unproven](#browser-phase) above for why that matters.
