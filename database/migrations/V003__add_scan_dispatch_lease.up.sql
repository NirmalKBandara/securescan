ALTER TABLE scan_jobs
    ADD COLUMN dispatch_lease_token uuid,
    ADD COLUMN dispatch_lease_expires_at timestamptz,
    ADD CONSTRAINT scan_jobs_dispatch_lease_ck CHECK (
        (dispatch_lease_token IS NULL AND dispatch_lease_expires_at IS NULL)
        OR
        (status = 'QUEUED'
            AND scanner_scan_id IS NULL
            AND dispatch_lease_token IS NOT NULL
            AND dispatch_lease_expires_at IS NOT NULL)
    );

CREATE INDEX scan_jobs_dispatch_recovery_idx
    ON scan_jobs (dispatch_lease_expires_at, created_at, id)
    WHERE status = 'QUEUED' AND scanner_scan_id IS NULL;
