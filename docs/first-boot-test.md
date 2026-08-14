# First Boot Test

Use this checklist for the Phase 1 text/network image.

## Before Boot

- Confirm the machine has wired Ethernet connected.
- Confirm the Talaria server is reachable from the same switch/VLAN.
- Enter BIOS setup and select USB boot.
- Record model, CPU, RAM, GPU, NIC, and monitor details in `docs/hardware-inventory.md`.

## Boot Criteria

The machine should:

- Boot from the USB image.
- Show the Talaria Display OS console splash.
- Reach BusyBox userspace.
- Bring up wired networking with DHCP.
- Create `/data/talaria/phase1.log`.
- Create `/data/talaria/data-mount.log`.
- Create `/data/talaria/network-wait.log`.
- Create `/data/talaria/display-mode.log`.
- Include interface, route, and ping output in the log.
- Resolve an effective display mode and print `TALARIA_MODE_RESOLVED` or `TALARIA_MODE_FALLBACK` to the console (see [`display-runtime-design.md`](display-runtime-design.md#mode-resolution)).

## Commands

On the target console:

```sh
ip addr show
ip route show
cat /data/talaria/data-mount.log
cat /data/talaria/network-wait.log
cat /data/talaria/phase1.log
cat /data/talaria/display-mode.log
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

`S70talaria-mode-resolve` also retries on its own every 15 seconds (`TALARIA_MODE_RESOLVE_INTERVAL`), so the `restart` above is only for forcing an immediate re-check — the override still takes effect within one interval either way.

## Pass Criteria

- The machine boots unattended after BIOS setup.
- The Talaria splash appears before diagnostics finish.
- Network comes up without manual driver work.
- The Talaria server can be pinged.
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
