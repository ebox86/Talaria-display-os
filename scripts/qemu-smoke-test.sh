#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${1:-${OUTPUT_DIR:-$repo_root/output}/images/disk.img}"
memory="${QEMU_MEMORY:-1024}"
timeout_seconds="${QEMU_TIMEOUT_SECONDS:-120}"
log_file="${QEMU_SMOKE_LOG:-$repo_root/artifacts/qemu-smoke.log}"
screenshot_png="${QEMU_SCREENSHOT:-$repo_root/artifacts/qemu-screenshot.png}"

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "qemu-system-x86_64 is required." >&2
  exit 1
fi

if [[ ! -f "$image" ]]; then
  echo "Image not found: $image" >&2
  echo "Run ./scripts/build.sh first or pass an explicit disk image path." >&2
  exit 1
fi

mkdir -p "$(dirname "$log_file")" "$(dirname "$screenshot_png")"
rm -f "$log_file" "$screenshot_png"

work_dir="$(mktemp -d)"
monitor_sock="$work_dir/monitor.sock"
screenshot_ppm="$work_dir/screenshot.ppm"
trap 'rm -rf "$work_dir"' EXIT

echo "Booting $image in headless QEMU for up to ${timeout_seconds}s"

# Run in the background (not the previous `timeout --foreground` blocking
# call) so we can reach into the QEMU monitor mid-run and grab a
# screenshot right when the wait loop below stops, whether that's a pass
# or a timeout - a frame of "wherever it got stuck" is exactly what's
# useful for the failure case too.
qemu-system-x86_64 \
  -M pc \
  -m "$memory" \
  -drive "file=$image,format=raw,if=ide" \
  -nic user,model=e1000 \
  -display none \
  -monitor "unix:$monitor_sock,server,nowait" \
  -serial stdio \
  -no-reboot \
  > "$log_file" 2>&1 &
qemu_pid=$!

passed=0
waited=0
while [[ "$waited" -lt "$timeout_seconds" ]]; do
  if grep -q 'TALARIA_PHASE1_READY' "$log_file" 2>/dev/null \
    && grep -Eq 'TALARIA_MODE_RESOLVED|TALARIA_MODE_FALLBACK' "$log_file" 2>/dev/null; then
    passed=1
    break
  fi
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

# Best-effort screenshot via the QEMU monitor socket. Ask for PNG
# directly first (supported on newer QEMU); always also ask for PPM as
# a fallback in case that's not supported, and convert that if the
# direct PNG never showed up. Requires `socat` to talk to the monitor
# and imagemagick/netpbm to convert PPM - see scripts/ci-install-deps.sh.
# Not verified against a real QEMU version yet; if this silently
# produces nothing, that's the first thing to check, not a sign the
# smoke test itself is broken.
if [[ -S "$monitor_sock" ]] && command -v socat >/dev/null 2>&1; then
  printf 'screendump %s png\nscreendump %s\n' "$screenshot_png" "$screenshot_ppm" \
    | socat - "UNIX-CONNECT:$monitor_sock" >/dev/null 2>&1 || true
  sleep 1
fi

if [[ ! -s "$screenshot_png" ]] && [[ -f "$screenshot_ppm" ]]; then
  if command -v convert >/dev/null 2>&1; then
    convert "$screenshot_ppm" "$screenshot_png" 2>/dev/null || true
  elif command -v pnmtopng >/dev/null 2>&1; then
    pnmtopng "$screenshot_ppm" > "$screenshot_png" 2>/dev/null || true
  fi
fi

kill "$qemu_pid" 2>/dev/null || true
wait "$qemu_pid" 2>/dev/null || true

if [[ "$passed" -eq 1 ]]; then
  echo "QEMU smoke test passed. Phase 1 and mode-resolution markers found in $log_file"
  [[ -s "$screenshot_png" ]] && echo "Screenshot captured: $screenshot_png"
  exit 0
fi

echo "QEMU smoke test did not see the expected markers in $log_file" >&2
echo "Expected TALARIA_PHASE1_READY and one of TALARIA_MODE_RESOLVED/TALARIA_MODE_FALLBACK." >&2
echo "--- QEMU log tail ---" >&2
tail -n 120 "$log_file" >&2 || true
if [[ -s "$screenshot_png" ]]; then
  echo "Screenshot captured despite failure: $screenshot_png" >&2
fi

if [[ "$waited" -ge "$timeout_seconds" ]]; then
  echo "QEMU timed out before boot completed." >&2
else
  echo "QEMU exited before boot completed." >&2
fi

exit 1
