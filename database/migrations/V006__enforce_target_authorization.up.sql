-- A target can pass the allowlist and then be blocked because its second DNS
-- resolution becomes unsafe. Preserve the matched rule for that audit trail;
-- a blocked job must still never have reached the scanner.
ALTER TABLE scan_jobs
    DROP CONSTRAINT scan_jobs_blocked_ck,
    ADD CONSTRAINT scan_jobs_blocked_ck CHECK (
        status <> 'BLOCKED' OR scanner_scan_id IS NULL
    );
