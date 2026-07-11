CREATE TABLE IF NOT EXISTS runs (
    run_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_date TEXT NOT NULL,
    pipeline_version TEXT,
    outdir TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS samples (
    sample_id TEXT,
    run_id INTEGER,
    condition TEXT,
    qc_status TEXT,
    reads_before INTEGER,
    reads_after INTEGER,
    quant_path TEXT,
    FOREIGN KEY (run_id) REFERENCES runs(run_id),
    PRIMARY KEY (sample_id, run_id)
);
