ALTER TABLE audit_logs
    DROP CONSTRAINT audit_logs_scan_job_id_fkey,
    ADD CONSTRAINT audit_logs_scan_job_id_fkey
        FOREIGN KEY (scan_job_id) REFERENCES scan_jobs(id) ON DELETE RESTRICT,
    ADD CONSTRAINT audit_logs_scan_event_shape_ck CHECK (
        action NOT IN (
            'SCAN_REQUESTED', 'SCAN_BLOCKED', 'SCAN_STARTED',
            'SCAN_COMPLETED', 'SCAN_FAILED'
        )
        OR (
            scan_job_id IS NOT NULL
            AND owner_subject IS NOT NULL
            AND (
                (action = 'SCAN_REQUESTED'
                    AND actor_type = 'USER'
                    AND actor_subject = owner_subject
                    AND outcome = 'SUCCESS')
                OR (action = 'SCAN_BLOCKED'
                    AND actor_type = 'SERVICE'
                    AND outcome = 'DENIED')
                OR (action IN ('SCAN_STARTED', 'SCAN_COMPLETED')
                    AND actor_type = 'SERVICE'
                    AND outcome = 'SUCCESS')
                OR (action = 'SCAN_FAILED'
                    AND actor_type = 'SERVICE'
                    AND outcome = 'FAILURE')
            )
        )
    ),
    ADD CONSTRAINT audit_logs_scan_metadata_ck CHECK (
        CASE action
            WHEN 'SCAN_REQUESTED' THEN
                metadata ?& ARRAY['startPort', 'endPort']
                AND metadata - 'startPort' - 'endPort' = '{}'::jsonb
                AND jsonb_typeof(metadata -> 'startPort') = 'number'
                AND jsonb_typeof(metadata -> 'endPort') = 'number'
            WHEN 'SCAN_STARTED' THEN metadata = '{}'::jsonb
            WHEN 'SCAN_COMPLETED' THEN
                metadata ?& ARRAY['resultCount', 'durationNanos']
                AND metadata - 'resultCount' - 'durationNanos' = '{}'::jsonb
                AND jsonb_typeof(metadata -> 'resultCount') = 'number'
                AND jsonb_typeof(metadata -> 'durationNanos') = 'number'
            WHEN 'SCAN_BLOCKED' THEN
                metadata ? 'failureCode'
                AND metadata - 'failureCode' = '{}'::jsonb
                AND jsonb_typeof(metadata -> 'failureCode') = 'string'
            WHEN 'SCAN_FAILED' THEN
                metadata ? 'failureCode'
                AND metadata - 'failureCode' = '{}'::jsonb
                AND jsonb_typeof(metadata -> 'failureCode') = 'string'
            ELSE true
        END
    );

CREATE UNIQUE INDEX audit_logs_scan_lifecycle_uq
    ON audit_logs (scan_job_id, action)
    WHERE action IN (
        'SCAN_REQUESTED', 'SCAN_BLOCKED', 'SCAN_STARTED',
        'SCAN_COMPLETED', 'SCAN_FAILED'
    );
