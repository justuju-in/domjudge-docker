#!/usr/bin/env bash
set -euo pipefail

# fix_cgroup.sh
# Ensure kernel boot parameters enable memory cgroup accounting (and force cgroup v1 if needed)
# Usage: sudo ./scripts/fix_cgroup.sh [--reboot|-r]

REBOOT=false
if [[ "${1:-}" =~ ^(--reboot|-r)$ ]]; then
  REBOOT=true
fi

GRUB_FILE="/etc/default/grub"
BACKUP="${GRUB_FILE}.bak.$(date +%Y%m%d%H%M%S)"

echo "⚙️  This script will modify ${GRUB_FILE} to enable memory cgroup accounting."
echo "📦 A backup will be written to: ${BACKUP}"

if [[ ! -w "$GRUB_FILE" ]]; then
  echo "❌ Run this script with sudo/root to modify ${GRUB_FILE}." >&2
  exit 1
fi

cp "$GRUB_FILE" "$BACKUP"

# Required kernel flags
FLAGS=(
  "cgroup_enable=memory"
  "swapaccount=1"
  "systemd.unified_cgroup_hierarchy=0"
)

# Ensure GRUB_CMDLINE_LINUX_DEFAULT exists
if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
  echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' >> "$GRUB_FILE"
fi

# Inject missing flags
for flag in "${FLAGS[@]}"; do
  if ! grep -q "$flag" "$GRUB_FILE"; then
    echo "➕ Adding flag: $flag"
    sed -i -E "s#^(GRUB_CMDLINE_LINUX_DEFAULT=\")([^\"]*)(\".*)#\1\2 $flag\3#" "$GRUB_FILE"
  else
    echo "✔️  Flag already present: $flag"
  fi
done

echo "🔄 Updating grub configuration..."
if command -v update-grub >/dev/null 2>&1; then
  update-grub
elif command -v grub-mkconfig >/dev/null 2>&1 && [[ -d /boot/grub ]]; then
  grub-mkconfig -o /boot/grub/grub.cfg
elif command -v grub2-mkconfig >/dev/null 2>&1 && [[ -d /boot/grub2 ]]; then
  grub2-mkconfig -o /boot/grub2/grub.cfg
else
  echo "⚠️  Could not find a grub update command. Please run manually." >&2
  exit 1
fi

echo "✅ Grub updated. You must reboot for changes to take effect."
if $REBOOT; then
  echo "♻️  Rebooting now..."
  exec reboot
fi
