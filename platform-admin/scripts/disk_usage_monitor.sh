#!/usr/bin/env bash
# Monitors disk usage of the pipeline's data directories.
# Intended to run on a schedule (see cron setup) in a real platform deployment.
set -euo pipefail

THRESHOLD_PERCENT=80
WATCH_DIRS=("data" "db")
LOG_FILE="platform-admin/logs/disk_usage.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$(dirname "$LOG_FILE")"

for dir in "${WATCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo "[$TIMESTAMP] $dir size: $SIZE" >> "$LOG_FILE"
    fi
done

# Check overall filesystem usage (the volume this repo lives on)
USE_PERCENT=$(df -h . | tail -1 | awk '{print $5}' | tr -d '%')

if [ "$USE_PERCENT" -ge "$THRESHOLD_PERCENT" ]; then
    echo "[$TIMESTAMP] ALERT: Filesystem usage at ${USE_PERCENT}% (threshold: ${THRESHOLD_PERCENT}%)" >> "$LOG_FILE"
    echo "ALERT: Disk usage at ${USE_PERCENT}%, exceeds ${THRESHOLD_PERCENT}% threshold" >&2
    exit 1
else
    echo "[$TIMESTAMP] OK: Filesystem usage at ${USE_PERCENT}%" >> "$LOG_FILE"
fi
