#!/usr/bin/env bash
set -e

conda run --no-capture-output -n pipeline nextflow run main.nf "$@"

# Extract --outdir and --samplesheet from args if provided, else use defaults
OUTDIR="data/results"
SAMPLESHEET="data/samplesheet.csv"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --outdir) OUTDIR="$2"; shift 2 ;;
        --samplesheet) SAMPLESHEET="$2"; shift 2 ;;
        *) shift ;;
    esac
done

echo "Pipeline succeeded — logging run to database..."
python3 scripts/log_run_to_db.py \
    --outdir "$OUTDIR" \
    --samplesheet "$SAMPLESHEET" \
    --db db/pipeline_runs.db
