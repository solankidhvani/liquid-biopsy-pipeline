-- ------------------------------------------------------------------
-- schema.sql
--
-- PostgreSQL schema for sample tracking, QC status, and data-transfer
-- audit logging. This mirrors what the liquid-biopsy-pipeline's SQLite
-- audit layer does, migrated to Postgres with proper foreign keys and
-- constraints so referential integrity is enforced by the database
-- rather than by application code.
-- ------------------------------------------------------------------

DROP TABLE IF EXISTS audit_log CASCADE;
DROP TABLE IF EXISTS qc_results CASCADE;
DROP TABLE IF EXISTS file_transfers CASCADE;
DROP TABLE IF EXISTS samples CASCADE;
DROP TABLE IF EXISTS batches CASCADE;

-- A "batch" is a group of samples received together from the
-- sequencing centre, e.g. one flow cell / one shipment.
CREATE TABLE batches (
    batch_id        SERIAL PRIMARY KEY,
    batch_label     TEXT NOT NULL UNIQUE,
    sequencing_ctr  TEXT NOT NULL,
    received_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE samples (
    sample_id       TEXT PRIMARY KEY,          -- e.g. 'S0142'
    batch_id        INTEGER NOT NULL REFERENCES batches(batch_id),
    patient_hash    TEXT NOT NULL,             -- de-identified patient key
    sample_type     TEXT NOT NULL CHECK (sample_type IN ('tumor', 'normal', 'liquid_biopsy')),
    received_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          TEXT NOT NULL DEFAULT 'received'
                       CHECK (status IN ('received', 'processing', 'qc_passed', 'qc_failed', 'reported')),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_samples_batch ON samples(batch_id);
CREATE INDEX idx_samples_status ON samples(status);

-- File transfer verification: one row per file moved between the
-- sequencing centre and the HPC environment, with checksums on both
-- ends so a mismatch is caught rather than silently propagated.
CREATE TABLE file_transfers (
    transfer_id       SERIAL PRIMARY KEY,
    sample_id         TEXT NOT NULL REFERENCES samples(sample_id),
    file_name         TEXT NOT NULL,
    source_path       TEXT NOT NULL,
    dest_path         TEXT NOT NULL,
    source_checksum   TEXT NOT NULL,
    dest_checksum     TEXT,                    -- NULL until transfer completes
    file_size_bytes   BIGINT NOT NULL,
    transfer_started  TIMESTAMPTZ NOT NULL DEFAULT now(),
    transfer_finished TIMESTAMPTZ,
    verified          BOOLEAN NOT NULL DEFAULT FALSE,
    status            TEXT NOT NULL DEFAULT 'in_progress'
                         CHECK (status IN ('in_progress', 'verified', 'checksum_mismatch', 'failed'))
);

CREATE INDEX idx_transfers_sample ON file_transfers(sample_id);
CREATE INDEX idx_transfers_status ON file_transfers(status);

-- QC results per sample per pipeline stage.
CREATE TABLE qc_results (
    qc_id           SERIAL PRIMARY KEY,
    sample_id       TEXT NOT NULL REFERENCES samples(sample_id),
    stage           TEXT NOT NULL,             -- e.g. 'alignment', 'variant_calling'
    metric_name     TEXT NOT NULL,             -- e.g. 'mean_coverage', 'duplicate_rate'
    metric_value    NUMERIC NOT NULL,
    threshold_min   NUMERIC,
    threshold_max   NUMERIC,
    passed          BOOLEAN NOT NULL,
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_qc_sample ON qc_results(sample_id);
CREATE INDEX idx_qc_passed ON qc_results(passed);

-- General audit log: every meaningful state change, for turnaround-time
-- reporting and troubleshooting. Append-only by convention.
CREATE TABLE audit_log (
    log_id          SERIAL PRIMARY KEY,
    sample_id       TEXT REFERENCES samples(sample_id),
    event_type      TEXT NOT NULL,             -- e.g. 'status_change', 'transfer_verified', 'qc_failed'
    event_detail    TEXT,
    actor            TEXT NOT NULL DEFAULT 'pipeline',  -- 'pipeline' or a username
    logged_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_sample ON audit_log(sample_id);
CREATE INDEX idx_audit_event ON audit_log(event_type);
CREATE INDEX idx_audit_logged_at ON audit_log(logged_at);
