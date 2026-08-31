#!/usr/bin/env bash
set -euo pipefail

images_dir="${BINARIES_DIR:-}"

if [[ -z "$images_dir" ]]; then
  echo "BINARIES_DIR is not set; nothing to summarize."
  exit 0
fi

git_commit="unknown"
if command -v git >/dev/null 2>&1; then
  git_commit="$(git -C "${BR2_EXTERNAL_TALARIA_DISPLAY_OS_PATH:-.}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

cat > "$images_dir/talaria-display-os-manifest.txt" <<EOF
Talaria Display OS image artifacts
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Git commit: $git_commit

Expected current milestone:
- boot target x86_64 PC
- acquire wired DHCP
- render Talaria PNG diagnostics splash
- write diagnostics logs under /data/talaria
- resolve dashboard/signage/pairing/diagnostics mode from local config or server assignment
- supervise WPE/Cog browser for dashboard/signage/pairing targets

Primary output:
- disk.img
- talaria-display-os-manifest.txt
- SHA256SUMS

Next work:
- validate on real old hardware
- implement edge-api/workbench assignment and heartbeat endpoints
EOF

(
  cd "$images_dir"
  if [[ -f disk.img ]]; then
    sha256sum disk.img > SHA256SUMS
  fi
)

echo "Wrote $images_dir/talaria-display-os-manifest.txt"
