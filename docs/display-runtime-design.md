# Display Runtime Design

Talaria Display OS should treat the screen as a managed Talaria endpoint, not as a dashboard-only device. The same OS should support production dashboards, digital signage, and diagnostics without rebuilding the image for each use case.

## Goals

- Boot unattended on old x86_64 workstations.
- Persist identity and runtime configuration under `/data/talaria`.
- Let the Talaria server decide what a display endpoint should render.
- Support dashboard and signage modes through the same browser/runtime stack.
- Fall back to local diagnostics when the server or configured content is unavailable.

## Runtime Config

The baked-in default lives at:

```text
/etc/talaria/display.conf
```

The writable override lives at:

```text
/data/talaria/display.conf
```

Expected fields:

```sh
TALARIA_SERVER_HOST=talaria.local
TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=http://talaria.local:5173/dashboard/
TALARIA_DEVICE_ID=unconfigured
```

Planned display modes:

- `dashboard`: production status board, delivery board, KPI views, or other operational screens.
- `signage`: Talaria-managed static or animated digital signage.
- `diagnostics`: local status and recovery screen.

## Server Contract

The OS should eventually call the Talaria server with `TALARIA_DEVICE_ID` and receive:

- assigned mode
- content URL or playlist URL
- refresh/retry policy
- display name/location
- health reporting interval
- emergency override content, if any

Until that exists, `TALARIA_DISPLAY_URL` is the direct boot target for the browser phase.

## Browser Phase

The first browser implementation should launch WPE WebKit/Cog against `TALARIA_DISPLAY_URL`. The launcher should:

- wait for networking
- verify `/data` is mounted
- load config from `/data/talaria/display.conf` when present
- render diagnostics if the configured URL cannot be reached
- retry the configured URL without requiring reboot

## Signage Implications

Signage should be server-managed content rendered by the display endpoint, not baked into the OS image. Static images, short animations, menu-style boards, and promotion screens should all be content assignments from Talaria, while Display OS stays a stable appliance runtime.
