#!/usr/bin/env bash
set -euo pipefail

images_dir="${BINARIES_DIR:-}"

if [[ -z "$images_dir" ]]; then
  echo "BINARIES_DIR is not set; nothing to summarize."
  exit 0
fi

git_commit="unknown"
if command -v git >/dev/null 2>&1; then
  git_commit="$(git -C "${BR2_EXTERNAL_TALARIA_DASHBOARD_OS_PATH:-.}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

cat > "$images_dir/talaria-dashboard-os-manifest.txt" <<EOF
Talaria Dashboard OS phase 1 image artifacts
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Git commit: $git_commit

Expected first milestone:
- boot target x86_64 PC
- acquire wired DHCP
- write /data/talaria/phase1.log
- ping configured TALARIA_SERVER_HOST when set

Primary output:
- disk.img
- talaria-dashboard-os-manifest.txt
- SHA256SUMS

Next work:
- validate on real old hardware
- add WPE WebKit/Cog after text/network bring-up succeeds
EOF

(
  cd "$images_dir"
  if [[ -f disk.img ]]; then
    sha256sum disk.img > SHA256SUMS
  fi
)

echo "Wrote $images_dir/talaria-dashboard-os-manifest.txt"
