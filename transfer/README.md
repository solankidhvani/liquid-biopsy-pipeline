# File Transfer Verification

A script for moving genomic/clinical files between a sequencing centre and
an HPC environment with checksum verification on both ends — so a
transfer that completes "successfully" but silently corrupts data doesn't
go unnoticed.

## Why this exists

`rsync` or `scp` finishing without an error doesn't guarantee the file
that lands on the HPC side is byte-identical to the one that left the
sequencing centre — network issues, disk errors, or an interrupted
transfer can all produce a file that's the right size but wrong content.
This script checksums the source before transfer, checksums the
destination after, and only calls it "verified" if they match — logging
every outcome (verified, mismatched, or failed) to an audit CSV.

## Files

| File | Purpose |
|---|---|
| `verify_transfer.py` | The script. Copies a file or directory, checksums both sides (SHA-256, streamed in chunks so large BAMs/FASTQs don't need to fit in memory), and logs the result. |

## Usage

```bash
# Single file, local/mounted-path copy
python verify_transfer.py \
    --source data/S001_R1.fastq.gz \
    --dest /hpc/data/raw/S001_R1.fastq.gz \
    --backend local

# Whole directory, over rsync/SSH to a real remote host
python verify_transfer.py \
    --source /seqctr/raw/BATCH-014/ \
    --dest hpcuser@hpc.example.org:/data/raw/BATCH-014/ \
    --backend rsync

# Re-verify a file that was already transferred, without re-copying it
python verify_transfer.py \
    --source data/S001_R1.fastq.gz \
    --dest /hpc/data/raw/S001_R1.fastq.gz \
    --verify-only
```

Exit code is `0` if every file verified cleanly, `1` if anything
mismatched or failed — meant to be used directly in a cron job:

```bash
verify_transfer.py --source ... --dest ... --backend rsync || alert_team.sh
```

## Tested behaviour

This was run against real files (not just read through) to confirm three
outcomes:

1. **Clean transfer** — 3 files, including one in a subdirectory, all
   verified with matching SHA-256 checksums, exit code 0.
2. **Corrupted transfer** — one destination file was deliberately
   bit-flipped after copying; `--verify-only` correctly flagged it as
   `checksum_mismatch` with both checksums shown, exit code 1.
3. **Missing file** — pointing at a nonexistent source correctly logs a
   `failed` status with a clear error message rather than crashing,
   exit code 1.

Example output for a run with one corrupted file:

```
Verifying: test_source/S001_R1.fastq.gz -> test_dest/S001_R1.fastq.gz
  OK  sha256=4ae39643cbf5... (5,000,000 bytes)
Verifying: test_source/S001_R2.fastq.gz -> test_dest/S001_R2.fastq.gz
  MISMATCH  source=999da1873787... dest=61b4ee1001bc...
Verifying: test_source/subdir/S002_R1.fastq.gz -> test_dest/subdir/S002_R1.fastq.gz
  OK  sha256=d7f0f7cc41dc... (2,000,000 bytes)

2 verified, 1 mismatched, 0 failed (of 3 total). Audit log: logs/transfer_audit.csv
```

## Audit log

Every run appends to `logs/transfer_audit.csv` (path configurable via
`--audit-csv`):

```
started_at,finished_at,file_name,source_path,dest_path,source_checksum,dest_checksum,file_size_bytes,status,error
2026-08-20T20:32:40+00:00,2026-08-20T20:32:40+00:00,S001_R2.fastq.gz,...,999da18...,61b4ee1...,3000000,checksum_mismatch,
```

This is intentionally flat/tabular so it can be loaded straight into the
`file_transfers` table from the `postgres/` reporting layer in this repo
(`source_checksum`/`dest_checksum`/`status` map directly onto that
table's columns), or into any spreadsheet for a manual audit.

## Design notes

- **SHA-256, streamed in 8MB chunks** — genomic files can be tens of GB;
  reading the whole file into memory to hash it isn't viable.
- **rsync needs its destination directory to exist first** for a
  single-file copy (unlike `cp`) — the script creates it automatically
  for local/mounted destination paths. For a genuinely remote
  destination, the remote directory must already exist; this is a real
  constraint of rsync itself.
- **`--verify-only`** exists specifically so this script can be run a
  second time, independently, after a transfer that used some other
  tool (or after the fact, as a periodic integrity re-check) — it
  doesn't assume it was the thing that did the copying.
- **Directory mode preserves relative paths** — every file under
  `--source` is checksummed and copied to the matching relative path
  under `--dest`, so nested batch/sample directory structures transfer
  correctly rather than flattening.
