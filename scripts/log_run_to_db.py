#!/usr/bin/env python3
"""
Logs a completed pipeline run into the SQLite tracking database.
Reads fastp JSON reports for QC pass/fail + read counts, and the
samplesheet for sample/condition mapping.

Usage:
    python3 scripts/log_run_to_db.py --outdir data/results --samplesheet data/samplesheet.csv --db db/pipeline_runs.db
"""
import argparse
import csv
import json
import sqlite3
import subprocess
from datetime import datetime
from pathlib import Path

def get_git_commit():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], text=True
        ).strip()
    except Exception:
        return "unknown"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--samplesheet", required=True)
    ap.add_argument("--db", required=True)
    args = ap.parse_args()

    outdir = Path(args.outdir)
    db_path = Path(args.db)
    db_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    conn.executescript(Path("db/schema.sql").read_text())

    run_date = datetime.now().isoformat(timespec="seconds")
    version = get_git_commit()

    cur = conn.execute(
        "INSERT INTO runs (run_date, pipeline_version, outdir) VALUES (?, ?, ?)",
        (run_date, version, str(outdir)),
    )
    run_id = cur.lastrowid

    with open(args.samplesheet) as f:
        reader = csv.DictReader(f)
        for row in reader:
            sample = row["sample"]
            condition = row["condition"]

            fastp_json = outdir / "fastp" / sample / f"{sample}_report.json"
            reads_before = reads_after = None
            qc_status = "unknown"
            if fastp_json.exists():
                data = json.loads(fastp_json.read_text())
                reads_before = data.get("summary", {}).get("before_filtering", {}).get("total_reads")
                reads_after = data.get("summary", {}).get("after_filtering", {}).get("total_reads")
                # simple pass/fail heuristic: retained >70% of reads
                if reads_before and reads_after:
                    qc_status = "pass" if reads_after / reads_before > 0.7 else "fail"

            quant_path = outdir / "salmon_quant" / sample / "quant.sf"

            conn.execute(
                """INSERT OR REPLACE INTO samples
                   (sample_id, run_id, condition, qc_status, reads_before, reads_after, quant_path)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (sample, run_id, condition, qc_status, reads_before, reads_after, str(quant_path)),
            )

    conn.commit()
    print(f"Logged run {run_id} ({run_date}, commit {version}) with samples from {args.samplesheet}")
    conn.close()

if __name__ == "__main__":
    main()
