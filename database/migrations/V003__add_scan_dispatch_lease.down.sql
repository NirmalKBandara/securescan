DROP INDEX scan_jobs_dispatch_recovery_idx;

ALTER TABLE scan_jobs
    DROP CONSTRAINT scan_jobs_dispatch_lease_ck,
    DROP COLUMN dispatch_lease_expires_at,
    DROP COLUMN dispatch_lease_token;
