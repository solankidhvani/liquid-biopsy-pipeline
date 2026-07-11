#!/usr/bin/env bash
# Installs cron jobs for platform monitoring and log rotation.
# Idempotent: safe to re-run without creating duplicate entries.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRON_MARKER="# liquid-biopsy-pipeline platform-admin"

CRON_JOBS="
$CRON_MARKER
0 * * * * cd $REPO_DIR && ./platform-admin/scripts/disk_usage_monitor.sh
0 2 * * 0 cd $REPO_DIR && ./platform-admin/scripts/rotate_logs.sh
"

( crontab -l 2>/dev/null | grep -v "$CRON_MARKER" ; echo "$CRON_JOBS" ) | crontab -

echo "Cron jobs installed:"
echo "  - Disk usage check: hourly"
echo "  - Log rotation: weekly (Sundays at 2am)"
crontab -l | grep -A2 "$CRON_MARKER"
