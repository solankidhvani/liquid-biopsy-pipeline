-- ------------------------------------------------------------------
-- reporting_queries.sql
--
-- Example reporting / audit queries against the schema in schema.sql.
-- Each query is written to answer a specific operational question a
-- bioinformatics/data coordination team would actually ask.
-- ------------------------------------------------------------------


-- 1. TURNAROUND TIME by batch: how long from sample receipt to
--    "reported" status, in days. Coordinators use this to spot
--    batches that are falling behind SLA.
SELECT
    b.batch_label,
    b.sequencing_ctr,
    COUNT(s.sample_id)                                             AS total_samples,
    COUNT(*) FILTER (WHERE s.status = 'reported')                  AS reported_samples,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (s.updated_at - s.received_at)) / 86400.0
    ) FILTER (WHERE s.status = 'reported'), 1)                     AS avg_turnaround_days
FROM batches b
JOIN samples s ON s.batch_id = b.batch_id
GROUP BY b.batch_id, b.batch_label, b.sequencing_ctr
ORDER BY b.received_at;


-- 2. FAILED QC AUDIT TRAIL: every sample that failed QC, with the
--    specific metric that failed and by how much, plus how long it
--    sat before anyone/anything logged the failure. This is the
--    query you'd run before a team standup.
SELECT
    s.sample_id,
    s.sample_type,
    b.batch_label,
    q.stage,
    q.metric_name,
    q.metric_value,
    q.threshold_min,
    q.threshold_max,
    q.recorded_at,
    al.event_detail AS audit_note
FROM qc_results q
JOIN samples s ON s.sample_id = q.sample_id
JOIN batches b ON b.batch_id = s.batch_id
LEFT JOIN audit_log al
       ON al.sample_id = s.sample_id
      AND al.event_type = 'qc_failed'
WHERE q.passed = FALSE
ORDER BY q.recorded_at DESC;


-- 3. REFERENTIAL INTEGRITY / DATA AUDIT: file transfers with a
--    checksum mismatch (data corrupted or altered in transit) or
--    stuck "in_progress" for more than 6 hours (stalled transfer
--    that needs manual follow-up). This is the kind of check that
--    would run nightly and alert the team.
SELECT
    ft.transfer_id,
    ft.sample_id,
    ft.file_name,
    ft.status,
    ft.source_checksum,
    ft.dest_checksum,
    ft.transfer_started,
    ft.transfer_finished,
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


-- 4. ORPHAN CHECK (referential integrity): samples referenced in
--    qc_results or file_transfers that no longer exist in the
--    samples table. In a well-behaved schema with foreign keys this
--    should always return zero rows -- this query is what you'd run
--    as a sanity check after a bulk import or manual data fix that
--    might have bypassed the ORM/constraints.
SELECT 'qc_results' AS source_table, q.qc_id AS row_id, q.sample_id
FROM qc_results q
LEFT JOIN samples s ON s.sample_id = q.sample_id
WHERE s.sample_id IS NULL

UNION ALL

SELECT 'file_transfers' AS source_table, ft.transfer_id AS row_id, ft.sample_id
FROM file_transfers ft
LEFT JOIN samples s ON s.sample_id = ft.sample_id
WHERE s.sample_id IS NULL;


-- 5. SAMPLES CURRENTLY STUCK: anything not in a terminal state
--    (reported / qc_failed) that hasn't been updated in over 48
--    hours -- a coordinator's "what needs attention today" list.
SELECT
    s.sample_id,
    s.sample_type,
    b.batch_label,
    s.status,
    s.updated_at,
    ROUND(EXTRACT(EPOCH FROM (now() - s.updated_at)) / 3600.0, 1) AS hours_since_update
FROM samples s
JOIN batches b ON b.batch_id = s.batch_id
WHERE s.status NOT IN ('reported', 'qc_failed')
  AND s.updated_at < now() - interval '48 hours'
ORDER BY s.updated_at ASC;


-- 6. WEEKLY THROUGHPUT / KPI SUMMARY: samples received vs. samples
--    reported per week, and QC pass rate -- the kind of rollup that
--    would feed a status report or dashboard.
SELECT
    date_trunc('week', s.received_at)                              AS week_of,
    COUNT(*)                                                       AS samples_received,
    COUNT(*) FILTER (WHERE s.status = 'reported')                  AS samples_reported,
    COUNT(*) FILTER (WHERE s.status = 'qc_failed')                 AS samples_qc_failed,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE s.status = 'qc_failed') / NULLIF(COUNT(*), 0), 1
    )                                                               AS qc_fail_rate_pct
FROM samples s
GROUP BY week_of
ORDER BY week_of;
