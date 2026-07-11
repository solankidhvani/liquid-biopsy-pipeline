# Platform Administration

Lightweight monitoring and maintenance scripts for running this pipeline as a persistent service, rather than a one-off analysis — the kind of operational tooling a shared bioinformatics platform needs beyond individual project runs.

## Scripts

- **`scripts/disk_usage_monitor.sh`** — Checks `data/` and `db/` sizes plus overall filesystem usage; logs to `logs/disk_usage.log` and alerts (non-zero exit + stderr) if usage exceeds 80%.
- **`scripts/rotate_logs.sh`** — Archives and compresses logs older than 30 days, preventing unbounded growth on a long-running server.
- **`setup_cron.sh`** — Idempotently installs both scripts into the current user's crontab (hourly disk check, weekly log rotation).

## Usage

```bash
# Run manually
./platform-admin/scripts/disk_usage_monitor.sh
./platform-admin/scripts/rotate_logs.sh

# Or install as scheduled jobs
./platform-admin/setup_cron.sh
```

## Design notes

- Scripts are idempotent and safe to re-run.
- Alerting is done via log entries + non-zero exit codes rather than email/Slack integration, keeping this dependency-free — in production this would hook into existing notification infrastructure (e.g. a platform's existing Slack webhook or PagerDuty integration).
