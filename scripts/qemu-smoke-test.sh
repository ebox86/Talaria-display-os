#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${1:-${OUTPUT_DIR:-$repo_root/output}/images/disk.img}"
memory="${QEMU_MEMORY:-1024}"
timeout_seconds="${QEMU_TIMEOUT_SECONDS:-120}"
log_file="${QEMU_SMOKE_LOG:-$repo_root/artifacts/qemu-smoke.log}"

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "qemu-system-x86_64 is required." >&2
  exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
  echo "timeout is required." >&2
  exit 1
fi

if [[ ! -f "$image" ]]; then
  echo "Image not found: $image" >&2
  echo "Run ./scripts/build.sh first or pass an explicit disk image path." >&2
  exit 1
fi

mkdir -p "$(dirname "$log_file")"
rm -f "$log_file"

echo "Booting $image in headless QEMU for up to ${timeout_seconds}s"
set +e
timeout --foreground "$timeout_seconds" qemu-system-x86_64 \
  -M pc \
  -m "$memory" \
  -drive "file=$image,format=raw,if=ide" \
  -nic user,model=e1000 \
  -display none \
  -monitor none \
  -serial stdio \
  -no-reboot \
  > "$log_file" 2>&1
status=$?
set -e

if grep -q 'TALARIA_PHASE1_READY' "$log_file"; then
  echo "QEMU smoke test passed. Phase 1 marker found in $log_file"
  exit 0
fi

echo "QEMU smoke test did not see TALARIA_PHASE1_READY in $log_file" >&2
echo "--- QEMU log tail ---" >&2
tail -n 120 "$log_file" >&2 || true

if [[ "$status" -eq 124 ]]; then
  echo "QEMU timed out before Phase 1 completed." >&2
else
  echo "QEMU exited with status $status before Phase 1 completed." >&2
fi

exit 1
