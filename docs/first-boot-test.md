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
- Include interface, route, and ping output in the log.

## Commands

On the target console:

```sh
ip addr show
ip route show
cat /data/talaria/data-mount.log
cat /data/talaria/network-wait.log
cat /data/talaria/phase1.log
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
```

## Pass Criteria

- The machine boots unattended after BIOS setup.
- The Talaria splash appears before diagnostics finish.
- Network comes up without manual driver work.
- The Talaria server can be pinged.
- `/data/talaria/phase1.log` survives reboot.
- `/data/talaria/data-mount.log` says the data partition mounted.

## Failures To Record

- Blank screen.
- Kernel panic.
- No boot device.
- No NIC detected.
- DHCP timeout.
- USB stick not visible after reboot.
- Boot takes longer than 90 seconds.
