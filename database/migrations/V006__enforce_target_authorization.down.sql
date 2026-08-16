UPDATE scan_jobs
   SET allowed_target_id = NULL
 WHERE status = 'BLOCKED' AND allowed_target_id IS NOT NULL;

ALTER TABLE scan_jobs
    DROP CONSTRAINT scan_jobs_blocked_ck,
    ADD CONSTRAINT scan_jobs_blocked_ck CHECK (
        status <> 'BLOCKED'
        OR (scanner_scan_id IS NULL AND allowed_target_id IS NULL)
    );
