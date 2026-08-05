DO $verification$
DECLARE
    expected_table text;
BEGIN
    FOREACH expected_table IN ARRAY ARRAY[
        'allowed_targets', 'scan_jobs', 'scan_results', 'audit_logs',
        'schema_migrations'
    ] LOOP
        IF to_regclass('public.' || expected_table) IS NULL THEN
            RAISE EXCEPTION 'missing expected table: %', expected_table;
        END IF;
    END LOOP;
END
$verification$;

DO $verification$
DECLARE
    expected_index text;
BEGIN
    FOREACH expected_index IN ARRAY ARRAY[
        'allowed_targets_global_hostname_uq',
        'allowed_targets_owner_hostname_uq',
        'allowed_targets_global_cidr_uq',
        'allowed_targets_owner_cidr_uq',
        'scan_jobs_owner_created_idx',
        'scan_jobs_owner_status_created_idx',
        'scan_jobs_created_idx',
        'scan_jobs_status_created_idx',
        'scan_jobs_queued_idx',
        'scan_jobs_dispatch_recovery_idx',
        'scan_jobs_allowed_target_idx',
        'scan_results_open_idx',
        'allowed_targets_active_hostname_idx',
        'allowed_targets_active_cidr_gist_idx',
        'allowed_targets_expiry_idx',
        'allowed_targets_created_idx',
        'audit_logs_occurred_idx',
        'audit_logs_action_occurred_idx',
        'audit_logs_actor_occurred_idx',
        'audit_logs_owner_occurred_idx',
        'audit_logs_request_idx',
        'audit_logs_scan_job_idx',
        'audit_logs_allowed_target_idx'
    ] LOOP
        IF to_regclass('public.' || expected_index) IS NULL THEN
            RAISE EXCEPTION 'missing expected index: %', expected_index;
        END IF;
    END LOOP;
END
$verification$;

DO $verification$
DECLARE
    expected_constraint text;
BEGIN
    FOREACH expected_constraint IN ARRAY ARRAY[
        'allowed_targets_pkey',
        'allowed_targets_kind_ck',
        'allowed_targets_value_ck',
        'allowed_targets_scope_ck',
        'allowed_targets_owner_ck',
        'allowed_targets_ports_ck',
        'allowed_targets_creator_ck',
        'allowed_targets_expiry_ck',
        'scan_jobs_pkey',
        'scan_jobs_scanner_scan_id_key',
        'scan_jobs_allowed_target_id_fkey',
        'scan_jobs_owner_ck',
        'scan_jobs_target_ck',
        'scan_jobs_ports_ck',
        'scan_jobs_status_ck',
        'scan_jobs_failure_ck',
        'scan_jobs_timeline_ck',
        'scan_jobs_scanner_id_ck',
        'scan_jobs_blocked_ck',
        'scan_jobs_duration_ck',
        'scan_jobs_dispatch_lease_ck',
        'scan_results_pkey',
        'scan_results_scan_job_id_fkey',
        'scan_results_port_ck',
        'scan_results_state_ck',
        'audit_logs_pkey',
        'audit_logs_scan_job_id_fkey',
        'audit_logs_allowed_target_id_fkey',
        'audit_logs_actor_type_ck',
        'audit_logs_actor_ck',
        'audit_logs_owner_ck',
        'audit_logs_action_ck',
        'audit_logs_outcome_ck',
        'audit_logs_metadata_object_ck'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint AS constraint_definition
            JOIN pg_namespace AS constraint_namespace
              ON constraint_namespace.oid = constraint_definition.connamespace
            WHERE constraint_namespace.nspname = 'public'
              AND constraint_definition.conname = expected_constraint
        ) THEN
            RAISE EXCEPTION 'missing expected constraint: %',
                expected_constraint;
        END IF;
    END LOOP;
END
$verification$;

DO $verification$
BEGIN
    IF (SELECT count(*) FROM schema_migrations) <> 3 THEN
        RAISE EXCEPTION 'expected exactly three applied migrations';
    END IF;

    IF (SELECT count(*) FROM allowed_targets
        WHERE id IN (
            '10000000-0000-4000-8000-000000000001'::uuid,
            '10000000-0000-4000-8000-000000000002'::uuid
        )) <> 2 THEN
        RAISE EXCEPTION 'development seed is incomplete';
    END IF;
END
$verification$;

-- Acceptance guard: a scan containing port zero must be rejected. The inner
-- block is a subtransaction, so this test never leaves a fixture behind.
DO $verification$
BEGIN
    BEGIN
        INSERT INTO scan_jobs (
            id, owner_subject, target, start_port, end_port, status
        ) VALUES (
            '20000000-0000-4000-8000-000000000001',
            'test:constraint-verification',
            'scan.dev.example',
            0,
            443,
            'QUEUED'
        );
        RAISE EXCEPTION 'invalid scan row was accepted';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;
END
$verification$;

-- Day 13 acceptance fixtures run in one outer transaction and are rolled back,
-- so verification can exercise lifecycle and ordering without retaining jobs.
BEGIN;

DO $verification$
DECLARE
    affected_rows bigint;
BEGIN
    INSERT INTO scan_jobs (
        id, owner_subject, target, start_port, end_port, status
    ) VALUES (
        '20000000-0000-4000-8000-000000000020',
        'test:dispatch-lease', 'scan.dev.example', 80, 80, 'QUEUED'
    );

    UPDATE scan_jobs
       SET dispatch_lease_token = '30000000-0000-4000-8000-000000000020',
           dispatch_lease_expires_at = CURRENT_TIMESTAMP + interval '15 seconds'
     WHERE id = '20000000-0000-4000-8000-000000000020'
       AND status = 'QUEUED' AND scanner_scan_id IS NULL
       AND (dispatch_lease_expires_at IS NULL
            OR dispatch_lease_expires_at <= CURRENT_TIMESTAMP);
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 1 THEN
        RAISE EXCEPTION 'first dispatcher did not acquire lease';
    END IF;

    UPDATE scan_jobs
       SET dispatch_lease_token = '30000000-0000-4000-8000-000000000021',
           dispatch_lease_expires_at = CURRENT_TIMESTAMP + interval '15 seconds'
     WHERE id = '20000000-0000-4000-8000-000000000020'
       AND status = 'QUEUED' AND scanner_scan_id IS NULL
       AND (dispatch_lease_expires_at IS NULL
            OR dispatch_lease_expires_at <= CURRENT_TIMESTAMP);
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 0 THEN
        RAISE EXCEPTION 'concurrent dispatcher replaced an active lease';
    END IF;

    UPDATE scan_jobs
       SET dispatch_lease_expires_at = CURRENT_TIMESTAMP - interval '1 second'
     WHERE id = '20000000-0000-4000-8000-000000000020';
    UPDATE scan_jobs
       SET dispatch_lease_token = '30000000-0000-4000-8000-000000000021',
           dispatch_lease_expires_at = CURRENT_TIMESTAMP + interval '15 seconds'
     WHERE id = '20000000-0000-4000-8000-000000000020'
       AND status = 'QUEUED' AND scanner_scan_id IS NULL
       AND dispatch_lease_expires_at <= CURRENT_TIMESTAMP;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 1 THEN
        RAISE EXCEPTION 'expired dispatch lease was not recoverable';
    END IF;
END
$verification$;

INSERT INTO scan_jobs (
    id, scanner_scan_id, owner_subject, target, start_port, end_port,
    status, created_at, updated_at, started_at
) VALUES (
    '20000000-0000-4000-8000-000000000010',
    '30000000-0000-4000-8000-000000000010',
    'test:day-13-owner',
    'scan.dev.example',
    22,
    443,
    'RUNNING',
    '2026-08-04T10:00:00Z',
    '2026-08-04T10:00:01Z',
    '2026-08-04T10:00:01Z'
);

-- A failed result batch must leave no partial observations behind.
DO $verification$
BEGIN
    BEGIN
        INSERT INTO scan_results (scan_job_id, address, port, state)
        VALUES (
            '20000000-0000-4000-8000-000000000010',
            '2001:db8::2',
            443,
            'OPEN'
        );
        INSERT INTO scan_results (scan_job_id, address, port, state)
        VALUES (
            '20000000-0000-4000-8000-000000000010',
            '2001:db8::2',
            0,
            'OPEN'
        );
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;

    IF EXISTS (
        SELECT 1 FROM scan_results
        WHERE scan_job_id = '20000000-0000-4000-8000-000000000010'
    ) THEN
        RAISE EXCEPTION 'failed result batch left partial rows';
    END IF;
END
$verification$;

INSERT INTO scan_results (scan_job_id, address, port, state, observed_at)
VALUES
    ('20000000-0000-4000-8000-000000000010', '2001:db8::2', 443,
     'OPEN', '2026-08-04T10:00:02Z'),
    ('20000000-0000-4000-8000-000000000010', '192.0.2.10', 80,
     'CLOSED', '2026-08-04T10:00:02Z'),
    ('20000000-0000-4000-8000-000000000010', '192.0.2.10', 22,
     'OPEN', '2026-08-04T10:00:02Z');

UPDATE scan_jobs
SET status = 'COMPLETED', duration_nanos = 1500000,
    finished_at = '2026-08-04T10:00:02Z',
    updated_at = '2026-08-04T10:00:02Z'
WHERE id = '20000000-0000-4000-8000-000000000010'
  AND status IN ('QUEUED', 'RUNNING');

-- This models a retried completion after the first transaction committed. The
-- terminal-state predicate must prevent the retry from appending a new row.
WITH active_job AS (
    SELECT id
    FROM scan_jobs
    WHERE id = '20000000-0000-4000-8000-000000000010'
      AND status IN ('QUEUED', 'RUNNING')
    FOR UPDATE
)
INSERT INTO scan_results (scan_job_id, address, port, state)
SELECT id, '192.0.2.10', 443, 'OPEN'
FROM active_job
ON CONFLICT (scan_job_id, address, port) DO NOTHING;

INSERT INTO scan_jobs (
    id, owner_subject, target, start_port, end_port, status,
    created_at, updated_at
) VALUES
    ('20000000-0000-4000-8000-000000000002', 'test:history-owner',
     'second.dev.example', 1, 2, 'QUEUED',
     '2026-08-04T09:00:00Z', '2026-08-04T09:00:00Z'),
    ('20000000-0000-4000-8000-000000000003', 'test:history-owner',
     'third.dev.example', 1, 2, 'QUEUED',
     '2026-08-04T09:00:00Z', '2026-08-04T09:00:00Z');

DO $verification$
DECLARE
    ordered_results text[];
    ordered_history uuid[];
BEGIN
    SELECT array_agg(address::text || ':' || port ORDER BY address, port)
    INTO ordered_results
    FROM scan_results
    WHERE scan_job_id = '20000000-0000-4000-8000-000000000010'
      AND EXISTS (
          SELECT 1 FROM scan_jobs
          WHERE scan_jobs.id = scan_results.scan_job_id
            AND owner_subject = 'test:day-13-owner'
      );

    IF ordered_results <> ARRAY[
        '192.0.2.10:22', '192.0.2.10:80', '2001:db8::2:443'
    ] THEN
        RAISE EXCEPTION 'scan result order or retry safety is incorrect: %',
            ordered_results;
    END IF;

    IF EXISTS (
        SELECT 1 FROM scan_results
        WHERE scan_job_id = '20000000-0000-4000-8000-000000000010'
          AND EXISTS (
              SELECT 1 FROM scan_jobs
              WHERE scan_jobs.id = scan_results.scan_job_id
                AND owner_subject = 'test:other-owner'
          )
    ) THEN
        RAISE EXCEPTION 'cross-owner result lookup returned rows';
    END IF;

    SELECT array_agg(id)
    INTO ordered_history
    FROM (
        SELECT id
        FROM scan_jobs
        WHERE owner_subject = 'test:history-owner'
        ORDER BY created_at DESC, id DESC
    ) AS stable_history;

    IF ordered_history <> ARRAY[
        '20000000-0000-4000-8000-000000000003'::uuid,
        '20000000-0000-4000-8000-000000000002'::uuid
    ] THEN
        RAISE EXCEPTION 'scan history tie-break order is incorrect: %',
            ordered_history;
    END IF;
END
$verification$;

ROLLBACK;

SELECT 'database verification passed' AS result;
