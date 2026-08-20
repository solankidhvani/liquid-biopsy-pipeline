#!/usr/bin/env python3
"""
run_audit_report.py

Connects to the genomics_tracking Postgres database and runs the
transfer-integrity audit query, printing anything that needs human
follow-up. Intended as a starting point for a scheduled (cron) job
that emails/Slacks a daily summary to the data coordination team.

Usage:
    python run_audit_report.py --host localhost --port 5432 \
        --dbname genomics_tracking --user genomics

    # Password can also be set via PGPASSWORD env var instead of --password
"""

from __future__ import annotations

import argparse
import os
import sys

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    sys.exit(
        "Missing dependency: psycopg2-binary\n"
        "Install with: pip install psycopg2-binary --break-system-packages"
    )


TRANSFER_AUDIT_QUERY = """
SELECT
    ft.transfer_id,
    ft.sample_id,
    ft.file_name,
    ft.status,
    ft.transfer_started,
    CASE
        WHEN ft.status = 'checksum_mismatch' THEN 'CORRUPTED IN TRANSIT'
        WHEN ft.status = 'in_progress'
             AND ft.transfer_started < now() - interval '6 hours' THEN 'STALLED - NEEDS FOLLOW-UP'
        ELSE 'OK'
    END AS flag
FROM file_transfers ft
WHERE ft.status IN ('checksum_mismatch', 'failed')
   OR (ft.status = 'in_progress' AND ft.transfer_started < now() - interval '6 hours')
ORDER BY ft.transfer_started;
"""

STUCK_SAMPLES_QUERY = """
SELECT
    s.sample_id,
    s.status,
    ROUND(EXTRACT(EPOCH FROM (now() - s.updated_at)) / 3600.0, 1) AS hours_since_update
FROM samples s
WHERE s.status NOT IN ('reported', 'qc_failed')
  AND s.updated_at < now() - interval '48 hours'
ORDER BY s.updated_at ASC;
"""


def connect(args: argparse.Namespace):
    return psycopg2.connect(
        host=args.host,
        port=args.port,
        dbname=args.dbname,
        user=args.user,
        password=args.password or os.environ.get("PGPASSWORD"),
    )


def run_report(conn) -> int:
    """Runs the audit queries and prints findings. Returns an exit
    code (0 = clean, 1 = issues found) so this can drive alerting in
    a cron job (e.g. `run_audit_report.py || send_alert`)."""

    issues_found = 0

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(TRANSFER_AUDIT_QUERY)
        transfer_issues = cur.fetchall()

        cur.execute(STUCK_SAMPLES_QUERY)
        stuck_samples = cur.fetchall()

    print("=" * 60)
    print("FILE TRANSFER INTEGRITY AUDIT")
    print("=" * 60)
    if transfer_issues:
        for row in transfer_issues:
            print(f"  [{row['flag']}] sample={row['sample_id']} "
                  f"file={row['file_name']} status={row['status']} "
                  f"started={row['transfer_started']}")
        issues_found += len(transfer_issues)
    else:
        print("  No transfer issues found.")

    print()
    print("=" * 60)
    print("SAMPLES NEEDING ATTENTION (no update in 48h)")
    print("=" * 60)
    if stuck_samples:
        for row in stuck_samples:
            print(f"  sample={row['sample_id']} status={row['status']} "
                  f"idle_hours={row['hours_since_update']}")
        issues_found += len(stuck_samples)
    else:
        print("  No stuck samples found.")

    print()
    print(f"Total items flagged: {issues_found}")
    return 1 if issues_found else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--dbname", default="genomics_tracking")
    parser.add_argument("--user", default="genomics")
    parser.add_argument("--password", default=None, help="Or set PGPASSWORD env var")
    args = parser.parse_args()

    try:
        conn = connect(args)
    except psycopg2.OperationalError as e:
        sys.exit(f"Could not connect to database: {e}")

    try:
        exit_code = run_report(conn)
    finally:
        conn.close()

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
