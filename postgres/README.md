# Sample Tracking & Audit: PostgreSQL Schema + Reporting Queries

A PostgreSQL schema and reporting layer for tracking samples through a
genomics pipeline — from receipt, through file transfer and QC, to final
report — with an audit trail designed for turnaround-time and data-integrity
reporting.

## Why this exists

Tracking "did this sample's data arrive intact, pass QC, and get reported
on time" across dozens or hundreds of samples needs more than log files —
it needs a schema with real foreign keys and constraints, so referential
integrity is enforced by the database, and queries that can actually
answer "what needs attention today."

## Files

| File | Purpose |
|---|---|
| `schema.sql` | Tables: `batches`, `samples`, `file_transfers`, `qc_results`, `audit_log`. Foreign keys and `CHECK` constraints enforce valid states at the database level. |
| `seed_data.sql` | Realistic sample data, including a deliberately seeded checksum mismatch, a stalled transfer, and a failed-QC sample — so the reporting queries have something real to find. |
| `reporting_queries.sql` | Six queries answering real operational questions: turnaround time by batch, failed-QC audit trail, transfer integrity (checksum mismatches + stalled transfers), an orphan/referential-integrity check, stuck-sample list, and weekly KPI rollup. |
| `run_audit_report.py` | Python script that connects to the database and runs the transfer-integrity and stuck-sample checks, printing flagged items and exiting non-zero if anything needs attention — built to be dropped into a cron job. |
| `docker-compose.yml` | Spins up Postgres 16 with the schema and seed data loaded automatically, so all of this is runnable in one command with no manual setup. |

## Run it

```bash
docker compose up -d
# wait a few seconds for the healthcheck to pass, then:
docker compose exec db psql -U genomics -d genomics_tracking -f /docker-entrypoint-initdb.d/../reporting_queries.sql
```

Or, to run the queries directly:

```bash
docker compose exec -T db psql -U genomics -d genomics_tracking < reporting_queries.sql
```

To run the Python audit report against the containerized database:

```bash
pip install psycopg2-binary --break-system-packages
PGPASSWORD=genomics_dev_only python run_audit_report.py \
    --host localhost --dbname genomics_tracking --user genomics
```

Expected output includes one flagged checksum mismatch and one stalled
transfer (both seeded intentionally), plus a short list of samples that
haven't been updated in 48+ hours:

```
============================================================
FILE TRANSFER INTEGRITY AUDIT
============================================================
  [CORRUPTED IN TRANSIT] sample=S0142 file=S0142_R1.fastq.gz status=checksum_mismatch ...
  [STALLED - NEEDS FOLLOW-UP] sample=S0161 file=S0161_R1.fastq.gz status=in_progress ...

Total items flagged: 5
```

To tear down: `docker compose down -v`

## Design notes

- **Foreign keys instead of application-level checks.** `file_transfers`,
  `qc_results`, and `audit_log` all reference `samples.sample_id`, so a
  bad insert (e.g. a sample_id typo) fails at the database level rather
  than silently creating an orphaned row. Query 4 in `reporting_queries.sql`
  is the sanity check you'd run after any bulk import to confirm nothing
  slipped through.
- **Checksums stored on both ends of a transfer.** `file_transfers` has
  separate `source_checksum` and `dest_checksum` columns and a `status`
  that distinguishes `checksum_mismatch` from `in_progress` from
  `verified` — this is what actually catches corruption in transit,
  versus only checksumming the file once it lands.
- **`run_audit_report.py` returns a real exit code**, not just printed
  text, specifically so it can be wired into a scheduled job:
  `run_audit_report.py || send_alert.sh` is a one-line integration.
- **`docker-compose.yml` auto-loads schema + seed data** via Postgres's
  `docker-entrypoint-initdb.d` convention, so `docker compose up` is the
  entire setup step — no manual `createdb` or `psql -f` needed for a
  reviewer to see it work.
