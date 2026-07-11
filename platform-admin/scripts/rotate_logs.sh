#!/usr/bin/env bash
# Rotates and compresses pipeline logs older than RETENTION_DAYS.
# Prevents unbounded log growth on a long-running platform server.
set -euo pipefail

LOG_DIRS=("platform-admin/logs" ".nextflow.log*")
RETENTION_DAYS=30
ARCHIVE_DIR="platform-admin/logs/archive"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$ARCHIVE_DIR"

# Compress and archive logs older than retention period
find platform-admin/logs -maxdepth 1 -name "*.log" -mtime +"$RETENTION_DAYS" -print0 2>/dev/null | \
while IFS= read -r -d '' file; do
    gzip -c "$file" > "$ARCHIVE_DIR/$(basename "$file").$(date +%Y%m%d).gz"
    rm "$file"
    echo "[$TIMESTAMP] Archived and removed: $file"
done

echo "[$TIMESTAMP] Log rotation complete" >> platform-admin/logs/rotation.log
