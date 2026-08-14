# Display Runtime Design

Talaria Display OS should treat the screen as a managed Talaria endpoint, not as a dashboard-only device. The same OS image should support production dashboards, digital signage, and local diagnostics without rebuilding the image per use case, and it should degrade to a safe local state whenever the server or configured content is unavailable.

This is a design document. It describes the intended mode model, config contract, and fallback behavior ahead of the runtime code that implements them. Phase 1 (console bring-up, networking, `/data` mount, diagnostics logging) is already implemented under `external/board/talaria/display-x86_64/rootfs_overlay/`. Phase 3 is this design plus the mode-resolution groundwork; the WPE/Cog browser launcher described in [Browser Phase](#browser-phase) is a later phase's implementation work, not part of this PR.

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
S7x talaria-mode-resolve  (new) decide effective mode, hand off to launcher
S8x talaria-browser       (future) launch WPE/Cog against the resolved target, or
                           stay in diagnostics if resolution failed
```

Resolution logic, in order:

1. Source `/etc/talaria/display.conf`, then `/data/talaria/display.conf` if present, per the precedence above.
2. If `TALARIA_DISPLAY_MODE` is not one of `dashboard`, `signage`, `diagnostics` — fall back to `diagnostics`.
3. If the resolved mode is `dashboard` or `signage` and `TALARIA_DISPLAY_URL` is unset or not a well-formed `http(s)://` URL — fall back to `diagnostics`.
4. If the resolved mode is `dashboard` or `signage`, probe reachability of `TALARIA_DISPLAY_URL` (or at minimum `TALARIA_SERVER_HOST`) the same way `S60talaria-phase1` already pings the server host — if unreachable, hold in `diagnostics` and keep retrying rather than launching a browser at a dead URL.
5. Otherwise, hand the resolved mode and URL to the browser launcher.

This keeps `diagnostics` as both a first-class mode an operator can pin a device to, and the automatic result of every failure path above.

## Fallback Behavior

Fallback to `diagnostics` is triggered by any of:

- `/data` partition not mounted (see `S20talaria-data`'s existing failure path — it already continues rather than halting).
- No default route within the existing 30s network-wait window.
- `/data/talaria/display.conf` present but unparseable, or absent along with a missing/invalid `/etc/talaria/display.conf` default.
- `TALARIA_DISPLAY_MODE` set to anything other than `dashboard`, `signage`, or `diagnostics`.
- `TALARIA_DISPLAY_URL` unset, malformed, or unreachable for `dashboard`/`signage`.
- Once the browser launcher exists: the configured URL loads but the browser process crashes or exits unexpectedly.

While in fallback, the device should:

- Show a diagnostics screen with device ID, resolved/attempted mode, configured URL, network state, and the specific reason fallback was triggered — not just "error."
- Keep logging to `/data/talaria` in the same append-friendly style as `phase1.log`, `data-mount.log`, and `network-wait.log`, so a technician can pull logs off the USB stick without a live session.
- Retry on a fixed interval without requiring a reboot. Each retry re-reads both config files from scratch, so dropping a corrected `/data/talaria/display.conf` and waiting (or restarting the relevant init script, as `first-boot-test.md` already documents for Phase 1) is enough to recover — no reflash.
- Never hard-fail the boot. A device that can never reach its server should still be a working diagnostics appliance indefinitely, not a device that stops responding.

The exact retry interval and backoff curve are implementation details for the phase that builds the resolver/launcher; this doc only commits to "bounded, automatic, no reboot required."

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

Out of scope for this PR; recorded here so mode resolution is designed against the real consumer. The first browser implementation should launch WPE WebKit/Cog against the resolved `TALARIA_DISPLAY_URL`. The launcher should:

- wait for the mode-resolution stage above to hand off a mode and URL
- verify `/data` is mounted before assuming any override config applies
- render diagnostics (per [Fallback Behavior](#fallback-behavior)) if the configured URL cannot be reached or the browser process dies
- retry the configured URL without requiring reboot, consistent with the fallback retry policy

## Open Questions

- Signage playlist format and how it differs from a single dashboard URL, once the server contract exists.
- Whether `diagnostics` gets its own browser-rendered page in the same launcher, or keeps the console splash indefinitely as the failure-safe path (keeping it console-only has the advantage of not depending on the thing that's failing).
- Process supervision for the browser (respawn policy, crash-loop backoff) once it's more than "launch and hope."
- Multi-monitor behavior, if any target hardware has more than one output.
- Health reporting transport and cadence back to the Talaria server.
