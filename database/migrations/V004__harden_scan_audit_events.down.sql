DROP INDEX audit_logs_scan_lifecycle_uq;

ALTER TABLE audit_logs
    DROP CONSTRAINT audit_logs_scan_metadata_ck,
    DROP CONSTRAINT audit_logs_scan_event_shape_ck,
    DROP CONSTRAINT audit_logs_scan_job_id_fkey,
    ADD CONSTRAINT audit_logs_scan_job_id_fkey
        FOREIGN KEY (scan_job_id) REFERENCES scan_jobs(id) ON DELETE SET NULL;
