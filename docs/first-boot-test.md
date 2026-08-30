# First Boot Test

Use this checklist for the display/network/browser image.

## Before Boot

- Confirm the machine has wired Ethernet connected.
- Confirm the Talaria server is reachable from the same switch/VLAN.
- Enter BIOS setup and select USB boot.
- Record model, CPU, RAM, GPU, NIC, and monitor details in `docs/hardware-inventory.md`.

## Boot Criteria

The machine should:

- Boot from the USB image.
- Show the Talaria Display OS PNG splash.
- Reach BusyBox userspace.
- Bring up wired networking with DHCP.
- Create `/data/talaria/phase1.log`.
- Create `/data/talaria/data-mount.log`.
- Create `/data/talaria/network-wait.log`.
- Create `/data/talaria/display-mode.log`.
- Create `/data/talaria/browser.log` if a browser-backed mode launches.
- Create `/data/talaria/hardware-report.log`.
- Include interface, route, and ping output in the log.
- Resolve an effective display mode and print `TALARIA_MODE_RESOLVED` or `TALARIA_MODE_FALLBACK` to the console (see [`display-runtime-design.md`](display-runtime-design.md#mode-resolution)).
- If the resolved mode is `dashboard`/`signage`/`pairing` and the browser stack built successfully, print `TALARIA_BROWSER_LAUNCH` to the console (see [`display-runtime-design.md`](display-runtime-design.md#browser-phase)). In `diagnostics` this stays local; no browser marker is expected.

## Commands

On the target console:

```sh
ip addr show
ip route show
cat /data/talaria/data-mount.log
cat /data/talaria/network-wait.log
cat /data/talaria/phase1.log
cat /data/talaria/display-mode.log
cat /data/talaria/browser.log
cat /data/talaria/hardware-report.log
```

If the Talaria host name is not resolvable yet, create a temporary override:

```sh
mkdir -p /data/talaria
cat > /data/talaria/display.conf <<'EOF'
TALARIA_SERVER_HOST=192.168.1.50
TALARIA_DISPLAY_MODE=dashboard
TALARIA_DISPLAY_URL=http://192.168.1.50:5173/dashboard/
TALARIA_DEVICE_ID=display-01
EOF
/etc/init.d/S60talaria-phase1 restart
/etc/init.d/S70talaria-mode-resolve restart
```

To test the future server-controlled path without changing the image, configure only identity and the control-plane base URL. Until the server implements the assignment endpoint, this should stay on the local pairing page:

```sh
cat > /data/talaria/display.conf <<'EOF'
TALARIA_SERVER_BASE_URL=http://192.168.1.50:17444
TALARIA_DEVICE_ID=display-01
TALARIA_DEVICE_TOKEN=1234
TALARIA_DISPLAY_MODE=pairing
EOF
/etc/init.d/S70talaria-mode-resolve restart
```

`S70talaria-mode-resolve` also retries on its own every 15 seconds (`TALARIA_MODE_RESOLVE_INTERVAL`), so the `restart` above is only for forcing an immediate re-check — the override still takes effect within one interval either way. `S80talaria-browser` picks up the change on its own next poll (every 5s, `TALARIA_BROWSER_POLL_INTERVAL`); restart it directly only to force an immediate recheck:

```sh
/etc/init.d/S80talaria-browser restart
```

## Pass Criteria

- The machine boots unattended after BIOS setup.
- The Talaria PNG splash appears before mode resolution.
- A fresh image reaches the local pairing page when the browser stack is healthy.
- Network comes up without manual driver work.
- The Talaria server can be reached by the intended application protocol. ICMP ping is still useful diagnostics when the network allows it, but some valid HTTP targets drop ping.
- `/data/talaria/phase1.log` survives reboot.
- `/data/talaria/data-mount.log` says the data partition mounted.
- `/data/talaria/display-mode.log` shows an `effective_mode` line, with a `fallback_reason` line only when fallback was actually triggered.

## Failures To Record

- Blank screen.
- Kernel panic.
- No boot device.
- No NIC detected.
- DHCP timeout.
- USB stick not visible after reboot.
- Boot takes longer than 90 seconds.
