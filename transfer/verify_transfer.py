#!/usr/bin/env python3
"""
verify_transfer.py

Copies a file (or every file in a directory) from a source location to
a destination, checksumming both ends, and logs a per-file audit record
showing whether the transfer was verified byte-for-byte or flagged as
a mismatch. Built for moving genomic/clinical files between a
sequencing centre and an HPC filesystem, where silently trusting a
completed `rsync`/`scp` isn't good enough for clinical data.

Supports two transfer backends:
  - local:  plain file copy (works for testing, or for local/mounted paths)
  - rsync:  shells out to rsync, for real remote transfers over SSH

Every run appends one row per file to a CSV audit log with a
timestamp, checksums, and status, so the log doubles as the record
you'd want for a data-transfer audit or turnaround-time report.

Usage:
    # Single file, local copy (e.g. testing, or same-filesystem move)
    python verify_transfer.py --source data/S001_R1.fastq.gz \
        --dest /hpc/data/raw/S001_R1.fastq.gz --backend local

    # Whole directory, over rsync/SSH
    python verify_transfer.py --source /seqctr/raw/BATCH-014/ \
        --dest hpcuser@hpc.example.org:/data/raw/BATCH-014/ --backend rsync

    # Re-verify an already-transferred file without re-copying it
    python verify_transfer.py --source data/S001_R1.fastq.gz \
        --dest /hpc/data/raw/S001_R1.fastq.gz --verify-only

Exit code is 0 if every file verified, 1 if any file failed or
mismatched — designed to be used directly in a cron job or CI step:
    verify_transfer.py ... || alert_team.sh
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


CHUNK_SIZE = 8 * 1024 * 1024  # 8 MB, reasonable for large genomic files


@dataclass
class TransferResult:
    file_name: str
    source_path: str
    dest_path: str
    source_checksum: str
    dest_checksum: str
    file_size_bytes: int
    status: str          # 'verified' | 'checksum_mismatch' | 'failed'
    error: str = ""
    started_at: str = ""
    finished_at: str = ""


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256sum(path: Path) -> str:
    """Stream the file in chunks rather than reading it whole into
    memory -- genomic files (BAMs, FASTQs) can be tens of GB."""
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(CHUNK_SIZE):
            h.update(chunk)
    return h.hexdigest()


def is_remote(path_str: str) -> bool:
    """Very lightweight check for an rsync-style remote spec
    (user@host:/path or host:/path), vs. a plain local path."""
    return ":" in path_str and not path_str.startswith(("/", "./", "../")) and not (
        len(path_str) > 1 and path_str[1] == ":"  # avoid false positive on Windows drive letters
    )


def local_copy(source: Path, dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, dest)


def rsync_copy(source: str, dest: str):
    """Shells out to rsync. -a preserves metadata; --checksum makes
    rsync itself compare checksums to decide whether to skip a file
    that already matches, on top of our own independent verification
    afterward.

    rsync (unlike `cp`) does not create the destination's parent
    directory for a single-file copy, so we create it first when the
    destination looks like a local path. For a genuinely remote
    destination (user@host:/path), the remote directory must already
    exist -- that's a real constraint of rsync itself, not something
    this script can fix from the local side.
    """
    if not is_remote(dest):
        Path(dest).parent.mkdir(parents=True, exist_ok=True)

    result = subprocess.run(
        ["rsync", "-a", "--checksum", source, dest],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"rsync failed (exit {result.returncode}): {result.stderr.strip()}")


def transfer_and_verify(
    source: Path,
    dest: Path,
    backend: str,
    verify_only: bool,
) -> TransferResult:
    file_name = source.name
    started_at = now_iso()

    result = TransferResult(
        file_name=file_name,
        source_path=str(source),
        dest_path=str(dest),
        source_checksum="",
        dest_checksum="",
        file_size_bytes=0,
        status="failed",
        started_at=started_at,
    )

    try:
        if not source.exists():
            raise FileNotFoundError(f"source file not found: {source}")
        if not source.is_file():
            raise ValueError(f"source is not a regular file: {source}")

        result.file_size_bytes = source.stat().st_size
        result.source_checksum = sha256sum(source)

        if not verify_only:
            if backend == "local":
                local_copy(source, dest)
            elif backend == "rsync":
                rsync_copy(str(source), str(dest))
            else:
                raise ValueError(f"unknown backend: {backend}")

        if not dest.exists():
            raise FileNotFoundError(f"destination file not found after transfer: {dest}")

        result.dest_checksum = sha256sum(dest)

        if result.source_checksum == result.dest_checksum:
            result.status = "verified"
        else:
            result.status = "checksum_mismatch"

    except Exception as e:
        result.status = "failed"
        result.error = str(e)

    result.finished_at = now_iso()
    return result


def collect_file_pairs(source: Path, dest: Path) -> list[tuple[Path, Path]]:
    """If source is a directory, pair up every file in it with the
    matching path under dest. If source is a single file, it's just
    the one pair."""
    if source.is_dir():
        pairs = []
        for f in sorted(source.rglob("*")):
            if f.is_file():
                rel = f.relative_to(source)
                pairs.append((f, dest / rel))
        return pairs
    return [(source, dest)]


def write_audit_row(csv_path: Path, result: TransferResult):
    file_exists = csv_path.exists()
    with csv_path.open("a", newline="") as f:
        writer = csv.writer(f)
        if not file_exists:
            writer.writerow([
                "started_at", "finished_at", "file_name", "source_path", "dest_path",
                "source_checksum", "dest_checksum", "file_size_bytes", "status", "error",
            ])
        writer.writerow([
            result.started_at, result.finished_at, result.file_name,
            result.source_path, result.dest_path, result.source_checksum,
            result.dest_checksum, result.file_size_bytes, result.status, result.error,
        ])


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", required=True, help="Source file or directory")
    parser.add_argument("--dest", required=True, help="Destination file or directory")
    parser.add_argument("--backend", choices=["local", "rsync"], default="local")
    parser.add_argument("--verify-only", action="store_true",
                         help="Skip the copy step; just checksum both sides and compare")
    parser.add_argument("--audit-csv", type=Path, default=Path("logs/transfer_audit.csv"))
    args = parser.parse_args()

    args.audit_csv.parent.mkdir(parents=True, exist_ok=True)

    source = Path(args.source)
    dest = Path(args.dest)

    if args.backend == "rsync" and (is_remote(args.source) or is_remote(args.dest)):
        # Remote rsync transfers of a whole directory are handled as one
        # rsync invocation (much faster than per-file), then verified
        # locally only where both sides happen to be reachable as paths.
        # For a genuinely remote destination, verification requires a
        # remote checksum step (e.g. via SSH) which is environment-specific
        # and left as an extension point -- see README.
        print("NOTE: remote rsync destination detected. This script copies via "
              "rsync but can only verify checksums on paths it can read directly. "
              "For a fully remote destination, run this script's --verify-only "
              "mode on the HPC side after transfer, pointed at the local copy.")

    pairs = collect_file_pairs(source, dest)
    if not pairs:
        sys.exit(f"No files found under source: {source}")

    results = []
    for src_file, dest_file in pairs:
        print(f"{'Verifying' if args.verify_only else 'Transferring'}: {src_file} -> {dest_file}")
        result = transfer_and_verify(src_file, dest_file, args.backend, args.verify_only)
        write_audit_row(args.audit_csv, result)
        results.append(result)

        if result.status == "verified":
            print(f"  OK  sha256={result.source_checksum[:12]}... "
                  f"({result.file_size_bytes:,} bytes)")
        elif result.status == "checksum_mismatch":
            print(f"  MISMATCH  source={result.source_checksum[:12]}... "
                  f"dest={result.dest_checksum[:12]}...")
        else:
            print(f"  FAILED  {result.error}")

    verified = sum(1 for r in results if r.status == "verified")
    mismatched = sum(1 for r in results if r.status == "checksum_mismatch")
    failed = sum(1 for r in results if r.status == "failed")

    print(f"\n{verified} verified, {mismatched} mismatched, {failed} failed "
          f"(of {len(results)} total). Audit log: {args.audit_csv}")

    sys.exit(0 if (mismatched == 0 and failed == 0) else 1)


if __name__ == "__main__":
    main()
