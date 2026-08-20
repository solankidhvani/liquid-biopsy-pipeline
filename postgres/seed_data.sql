-- ------------------------------------------------------------------
-- seed_data.sql
--
-- Realistic-looking sample data so the reporting queries return
-- something meaningful. Includes some intentionally messy/failing
-- cases (a checksum mismatch, a failed QC, a stalled transfer) so
-- the audit queries have something to actually find.
-- ------------------------------------------------------------------

INSERT INTO batches (batch_label, sequencing_ctr, received_at) VALUES
    ('BATCH-2026-014', 'Genome Sciences Centre',   now() - interval '12 days'),
    ('BATCH-2026-015', 'Genome Sciences Centre',   now() - interval '7 days'),
    ('BATCH-2026-016', 'BC Cancer Sequencing Core', now() - interval '2 days');

INSERT INTO samples (sample_id, batch_id, patient_hash, sample_type, received_at, status, updated_at) VALUES
    ('S0140', 1, 'ph_a1f9', 'tumor',         now() - interval '12 days', 'reported',   now() - interval '9 days'),
    ('S0141', 1, 'ph_a1f9', 'normal',        now() - interval '12 days', 'reported',   now() - interval '9 days'),
    ('S0142', 1, 'ph_b7c2', 'liquid_biopsy', now() - interval '12 days', 'qc_failed',  now() - interval '10 days'),
    ('S0150', 2, 'ph_c3e8', 'tumor',         now() - interval '7 days',  'qc_passed',  now() - interval '5 days'),
    ('S0151', 2, 'ph_c3e8', 'normal',        now() - interval '7 days',  'qc_passed',  now() - interval '5 days'),
    ('S0152', 2, 'ph_d9a1', 'liquid_biopsy', now() - interval '7 days',  'processing', now() - interval '1 days'),
    ('S0160', 3, 'ph_e2f4', 'tumor',         now() - interval '2 days',  'received',   now() - interval '2 days'),
    ('S0161', 3, 'ph_e2f4', 'normal',        now() - interval '2 days',  'processing', now() - interval '1 days');

-- File transfers: most verified cleanly, one checksum mismatch, one stalled.
INSERT INTO file_transfers
    (sample_id, file_name, source_path, dest_path, source_checksum, dest_checksum,
     file_size_bytes, transfer_started, transfer_finished, verified, status)
VALUES
    ('S0140', 'S0140_R1.fastq.gz', '/seqctr/raw/S0140_R1.fastq.gz', '/hpc/data/raw/S0140_R1.fastq.gz',
     'a3f5c8...e21', 'a3f5c8...e21', 4832991021,
     now() - interval '12 days', now() - interval '12 days' + interval '40 minutes', TRUE, 'verified'),

    ('S0141', 'S0141_R1.fastq.gz', '/seqctr/raw/S0141_R1.fastq.gz', '/hpc/data/raw/S0141_R1.fastq.gz',
     'b91d20...74a', 'b91d20...74a', 4711002233,
     now() - interval '12 days', now() - interval '12 days' + interval '38 minutes', TRUE, 'verified'),

    -- checksum mismatch: source and dest differ -> flagged, not verified
    ('S0142', 'S0142_R1.fastq.gz', '/seqctr/raw/S0142_R1.fastq.gz', '/hpc/data/raw/S0142_R1.fastq.gz',
     'c7e831...90f', 'c7e830...90f', 5011234567,
     now() - interval '12 days', now() - interval '12 days' + interval '52 minutes', FALSE, 'checksum_mismatch'),

    ('S0150', 'S0150_R1.fastq.gz', '/seqctr/raw/S0150_R1.fastq.gz', '/hpc/data/raw/S0150_R1.fastq.gz',
     'd4a719...bb2', 'd4a719...bb2', 4650012093,
     now() - interval '7 days', now() - interval '7 days' + interval '35 minutes', TRUE, 'verified'),

    -- in-progress / stalled transfer: no finish time, no dest checksum yet
    ('S0161', 'S0161_R1.fastq.gz', '/seqctr/raw/S0161_R1.fastq.gz', '/hpc/data/raw/S0161_R1.fastq.gz',
     'e88f12...c40', NULL, 4903312044,
     now() - interval '1 days', NULL, FALSE, 'in_progress');

-- QC results: mix of passing and failing metrics.
INSERT INTO qc_results (sample_id, stage, metric_name, metric_value, threshold_min, threshold_max, passed, recorded_at) VALUES
    ('S0140', 'alignment',       'mean_coverage',   142.3, 100, NULL, TRUE,  now() - interval '11 days'),
    ('S0140', 'alignment',       'duplicate_rate',  0.08,  NULL, 0.15, TRUE, now() - interval '11 days'),
    ('S0141', 'alignment',       'mean_coverage',   138.7, 100, NULL, TRUE,  now() - interval '11 days'),
    ('S0142', 'alignment',       'mean_coverage',   31.2,  80,  NULL, FALSE, now() - interval '10 days'),
    ('S0142', 'alignment',       'duplicate_rate',  0.29,  NULL, 0.15, FALSE, now() - interval '10 days'),
    ('S0150', 'variant_calling', 'ts_tv_ratio',     2.05,  1.9, 2.2,  TRUE,  now() - interval '5 days'),
    ('S0151', 'variant_calling', 'ts_tv_ratio',     2.11,  1.9, 2.2,  TRUE,  now() - interval '5 days'),
    ('S0152', 'alignment',       'mean_coverage',   95.4,  80,  NULL, TRUE,  now() - interval '1 days');

-- Audit log entries tied to the events above.
INSERT INTO audit_log (sample_id, event_type, event_detail, actor, logged_at) VALUES
    ('S0140', 'status_change',     'received -> processing',     'pipeline', now() - interval '12 days' + interval '1 hour'),
    ('S0140', 'status_change',     'processing -> reported',     'pipeline', now() - interval '9 days'),
    ('S0142', 'transfer_verified', 'checksum mismatch detected', 'pipeline', now() - interval '12 days' + interval '1 hour'),
    ('S0142', 'qc_failed',         'coverage below threshold (31.2x < 80x)', 'pipeline', now() - interval '10 days'),
    ('S0161', 'status_change',     'received -> processing',     'pipeline', now() - interval '1 days'),
    (NULL,    'system',            'nightly checksum audit job started', 'cron', now() - interval '6 hours');
