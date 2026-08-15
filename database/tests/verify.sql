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
        'audit_logs_allowed_target_idx',
        'audit_logs_scan_lifecycle_uq',
        'audit_logs_allowed_target_creation_uq',
        'audit_logs_allowed_target_disable_uq'
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
        'audit_logs_metadata_object_ck',
        'audit_logs_scan_event_shape_ck',
        'audit_logs_scan_metadata_ck',
        'audit_logs_allowed_target_event_shape_ck',
        'audit_logs_allowed_target_metadata_ck'
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
    IF (SELECT count(*) FROM schema_migrations) <> 5 THEN
        RAISE EXCEPTION 'expected exactly five applied migrations';
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

-- Acceptance guard
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

-- Day 25 owner isolation and audit attribution
INSERT INTO scan_jobs (
    id, owner_subject, target, start_port, end_port, status
) VALUES
    ('20000000-0000-4000-8000-000000000040', 'subject:alice',
     'alice.dev.example', 80, 80, 'QUEUED'),
    ('20000000-0000-4000-8000-000000000041', 'subject:bob',
     'bob.dev.example', 443, 443, 'QUEUED');

INSERT INTO audit_logs (
    id, actor_type, actor_subject, owner_subject, action, outcome,
    request_id, scan_job_id, metadata
) VALUES (
    '40000000-0000-4000-8000-000000000040', 'USER', 'subject:alice',
    'subject:alice', 'SCAN_REQUESTED', 'SUCCESS',
    '50000000-0000-4000-8000-000000000040',
    '20000000-0000-4000-8000-000000000040',
    '{"startPort":80,"endPort":80}'
);

DO $verification$
BEGIN
    IF (SELECT count(*) FROM scan_jobs
         WHERE owner_subject = 'subject:alice') <> 1 THEN
        RAISE EXCEPTION 'owner-scoped history exposed another user';
    END IF;
    IF EXISTS (
        SELECT 1 FROM scan_jobs
         WHERE id = '20000000-0000-4000-8000-000000000041'
           AND owner_subject = 'subject:alice'
    ) THEN
        RAISE EXCEPTION 'owner-scoped detail exposed another user';
    END IF;
    IF (SELECT count(*) FROM scan_jobs
         WHERE owner_subject IN ('subject:alice', 'subject:bob')) <> 2 THEN
        RAISE EXCEPTION 'administrator cross-owner query is incomplete';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM audit_logs
         WHERE scan_job_id = '20000000-0000-4000-8000-000000000040'
           AND actor_subject = 'subject:alice'
           AND owner_subject = 'subject:alice'
    ) THEN
        RAISE EXCEPTION 'authenticated audit attribution is missing';
    END IF;
END
$verification$;

ROLLBACK;

BEGIN;

INSERT INTO scan_jobs (
    id, scanner_scan_id, owner_subject, target, start_port, end_port,
    status, failure_code, duration_nanos, created_at, updated_at, started_at,
    finished_at
) VALUES (
    '20000000-0000-4000-8000-000000000030',
    '30000000-0000-4000-8000-000000000030',
    'test:day-15-owner', 'success.dev.example', 80, 81,
    'COMPLETED', NULL, 2000000,
    '2026-08-06T10:00:00Z', '2026-08-06T10:00:02Z',
    '2026-08-06T10:00:01Z', '2026-08-06T10:00:02Z'
), (
    '20000000-0000-4000-8000-000000000031', NULL,
    'test:day-15-owner', 'blocked.dev.example', 443, 443,
    'BLOCKED', 'BLOCKED_TARGET', NULL,
    '2026-08-06T11:00:00Z', '2026-08-06T11:00:01Z',
    NULL, '2026-08-06T11:00:01Z'
);

INSERT INTO scan_results (scan_job_id, address, port, state, observed_at)
VALUES
    ('20000000-0000-4000-8000-000000000030', '192.0.2.20', 80,
     'OPEN', '2026-08-06T10:00:02Z'),
    ('20000000-0000-4000-8000-000000000030', '192.0.2.20', 81,
     'CLOSED', '2026-08-06T10:00:02Z');

INSERT INTO audit_logs (
    id, occurred_at, actor_type, actor_subject, owner_subject, action,
    outcome, request_id, scan_job_id, metadata
) VALUES
    ('40000000-0000-4000-8000-000000000030', '2026-08-06T10:00:00Z',
     'USER', 'test:day-15-owner', 'test:day-15-owner', 'SCAN_REQUESTED',
     'SUCCESS', '50000000-0000-4000-8000-000000000030',
     '20000000-0000-4000-8000-000000000030',
     '{"startPort":80,"endPort":81}'),
    ('40000000-0000-4000-8000-000000000031', '2026-08-06T10:00:01Z',
     'SERVICE', 'securescan-api', 'test:day-15-owner', 'SCAN_STARTED',
     'SUCCESS', '50000000-0000-4000-8000-000000000030',
     '20000000-0000-4000-8000-000000000030', '{}'),
    ('40000000-0000-4000-8000-000000000032', '2026-08-06T10:00:02Z',
     'SERVICE', 'securescan-api', 'test:day-15-owner', 'SCAN_COMPLETED',
     'SUCCESS', '50000000-0000-4000-8000-000000000032',
     '20000000-0000-4000-8000-000000000030',
     '{"resultCount":2,"durationNanos":2000000}'),
    ('40000000-0000-4000-8000-000000000033', '2026-08-06T11:00:00Z',
     'USER', 'test:day-15-owner', 'test:day-15-owner', 'SCAN_REQUESTED',
     'SUCCESS', '50000000-0000-4000-8000-000000000033',
     '20000000-0000-4000-8000-000000000031',
     '{"startPort":443,"endPort":443}'),
    ('40000000-0000-4000-8000-000000000034', '2026-08-06T11:00:01Z',
     'SERVICE', 'securescan-api', 'test:day-15-owner', 'SCAN_BLOCKED',
     'DENIED', '50000000-0000-4000-8000-000000000033',
     '20000000-0000-4000-8000-000000000031',
     '{"failureCode":"BLOCKED_TARGET"}');

DO $verification$
DECLARE
    success_actions text[];
    blocked_actions text[];
BEGIN
    SELECT array_agg(action ORDER BY occurred_at)
      INTO success_actions
      FROM audit_logs
     WHERE scan_job_id = '20000000-0000-4000-8000-000000000030';
    IF success_actions <> ARRAY[
        'SCAN_REQUESTED', 'SCAN_STARTED', 'SCAN_COMPLETED'
    ] THEN
        RAISE EXCEPTION 'successful audit trail is incomplete: %',
            success_actions;
    END IF;

    SELECT array_agg(action ORDER BY occurred_at)
      INTO blocked_actions
      FROM audit_logs
     WHERE scan_job_id = '20000000-0000-4000-8000-000000000031';
    IF blocked_actions <> ARRAY['SCAN_REQUESTED', 'SCAN_BLOCKED'] THEN
        RAISE EXCEPTION 'blocked audit trail is incomplete: %', blocked_actions;
    END IF;

    IF (SELECT count(*) FROM scan_results
        WHERE scan_job_id = '20000000-0000-4000-8000-000000000030') <> 2
       OR EXISTS (
           SELECT 1 FROM scan_results
           WHERE scan_job_id = '20000000-0000-4000-8000-000000000031'
       ) THEN
        RAISE EXCEPTION 'successful or blocked result records are incorrect';
    END IF;

    IF EXISTS (
        SELECT 1 FROM audit_logs
         WHERE scan_job_id IN (
             '20000000-0000-4000-8000-000000000030',
             '20000000-0000-4000-8000-000000000031'
         )
           AND (request_id IS NULL OR owner_subject IS NULL
                OR actor_subject IS NULL OR occurred_at IS NULL
                OR metadata::text ~* '(authorization|bearer|credential|cookie|password|secret|token)')
    ) THEN
        RAISE EXCEPTION 'audit identity fields are missing or metadata is unsafe';
    END IF;
END
$verification$;

DO $verification$
BEGIN
    BEGIN
        INSERT INTO audit_logs (
            id, actor_type, actor_subject, owner_subject, action, outcome,
            request_id, scan_job_id, metadata
        ) VALUES (
            '40000000-0000-4000-8000-000000000035',
            'SERVICE', 'securescan-api', 'test:day-15-owner',
            'SCAN_COMPLETED', 'SUCCESS',
            '50000000-0000-4000-8000-000000000035',
            '20000000-0000-4000-8000-000000000030',
            '{"resultCount":2,"durationNanos":2000000}'
        );
        RAISE EXCEPTION 'duplicate lifecycle audit event was accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;
END
$verification$;

INSERT INTO scan_jobs (
    id, scanner_scan_id, owner_subject, target, start_port, end_port,
    status, created_at, updated_at, started_at
) VALUES (
    '20000000-0000-4000-8000-000000000032',
    '30000000-0000-4000-8000-000000000032',
    'test:day-15-owner', 'failure.dev.example', 22, 22, 'RUNNING',
    '2026-08-06T12:00:00Z', '2026-08-06T12:00:01Z',
    '2026-08-06T12:00:01Z'
);

DO $verification$
BEGIN
    BEGIN
        UPDATE scan_jobs
           SET status = 'FAILED', failure_code = 'SCANNER_FAILED',
               finished_at = '2026-08-06T12:00:02Z',
               updated_at = '2026-08-06T12:00:02Z'
         WHERE id = '20000000-0000-4000-8000-000000000032';
        INSERT INTO audit_logs (
            id, actor_type, actor_subject, owner_subject, action, outcome,
            request_id, scan_job_id, metadata
        ) VALUES (
            '40000000-0000-4000-8000-000000000036',
            'SERVICE', 'securescan-api', 'test:day-15-owner',
            'SCAN_FAILED', 'FAILURE',
            '50000000-0000-4000-8000-000000000036',
            '20000000-0000-4000-8000-000000000032',
            '{"failureCode":"SCANNER_FAILED","token":"forbidden"}'
        );
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    IF (SELECT status FROM scan_jobs
        WHERE id = '20000000-0000-4000-8000-000000000032') <> 'RUNNING' THEN
        RAISE EXCEPTION 'audit failure did not roll back lifecycle update';
    END IF;
END
$verification$;

ROLLBACK;

-- Day 30 allowed-target administration and immutable attribution
BEGIN;

INSERT INTO allowed_targets (
    id, target_kind, hostname_normalized, scope, start_port, end_port,
    created_by_subject
) VALUES (
    '10000000-0000-4000-8000-000000000030', 'HOSTNAME',
    'admin.dev.example', 'GLOBAL', 80, 443, 'subject:admin'
);

INSERT INTO allowed_targets (
    id, target_kind, target_cidr, scope, created_by_subject
) VALUES
(
    '10000000-0000-4000-8000-000000000031', 'IP',
    '192.0.2.30/32', 'GLOBAL', 'subject:admin'
), (
    '10000000-0000-4000-8000-000000000032', 'CIDR',
    '2001:db8::/48', 'GLOBAL', 'subject:admin'
);

INSERT INTO audit_logs (
    id, actor_type, actor_subject, action, outcome, request_id,
    allowed_target_id, metadata
) VALUES
    ('40000000-0000-4000-8000-000000000050', 'ADMIN', 'subject:admin',
     'ALLOW_TARGET_CREATED', 'SUCCESS',
     '50000000-0000-4000-8000-000000000050',
     '10000000-0000-4000-8000-000000000030',
     '{"targetKind":"HOSTNAME","target":"admin.dev.example"}'),
    ('40000000-0000-4000-8000-000000000051', 'ADMIN', 'subject:admin',
     'ALLOW_TARGET_CREATED', 'SUCCESS',
     '50000000-0000-4000-8000-000000000051',
     '10000000-0000-4000-8000-000000000031',
     '{"targetKind":"IP","target":"192.0.2.30"}'),
    ('40000000-0000-4000-8000-000000000052', 'ADMIN', 'subject:admin',
     'ALLOW_TARGET_CREATED', 'SUCCESS',
     '50000000-0000-4000-8000-000000000052',
     '10000000-0000-4000-8000-000000000032',
     '{"targetKind":"CIDR","target":"2001:db8::/48"}');

UPDATE allowed_targets
   SET enabled = false, updated_at = CURRENT_TIMESTAMP
 WHERE id = '10000000-0000-4000-8000-000000000030';

INSERT INTO audit_logs (
    id, actor_type, actor_subject, action, outcome, request_id,
    allowed_target_id, metadata
) VALUES (
    '40000000-0000-4000-8000-000000000053', 'ADMIN', 'subject:admin',
    'ALLOW_TARGET_DISABLED', 'SUCCESS',
    '50000000-0000-4000-8000-000000000053',
    '10000000-0000-4000-8000-000000000030', '{"enabled":false}'
);

DO $verification$
BEGIN
    IF (SELECT count(*) FROM allowed_targets
         WHERE id IN (
             '10000000-0000-4000-8000-000000000030',
             '10000000-0000-4000-8000-000000000031',
             '10000000-0000-4000-8000-000000000032'
         )) <> 3 THEN
        RAISE EXCEPTION 'hostname, exact IP, and CIDR targets were not stored';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM allowed_targets
         WHERE id = '10000000-0000-4000-8000-000000000031'
           AND target_kind = 'IP' AND masklen(target_cidr) = 32
    ) THEN
        RAISE EXCEPTION 'exact IP target was not stored as a host CIDR';
    END IF;
    IF EXISTS (
        SELECT 1 FROM audit_logs
         WHERE allowed_target_id IN (
             '10000000-0000-4000-8000-000000000030',
             '10000000-0000-4000-8000-000000000031',
             '10000000-0000-4000-8000-000000000032'
         )
           AND (actor_type <> 'ADMIN' OR actor_subject <> 'subject:admin'
                OR request_id IS NULL OR occurred_at IS NULL)
    ) THEN
        RAISE EXCEPTION 'allowed-target audit attribution is incomplete';
    END IF;
    IF (SELECT count(*) FROM audit_logs
         WHERE allowed_target_id = '10000000-0000-4000-8000-000000000030') <> 2
       OR (SELECT enabled FROM allowed_targets
            WHERE id = '10000000-0000-4000-8000-000000000030') THEN
        RAISE EXCEPTION 'allowed-target disable was not audited';
    END IF;
END
$verification$;

DO $verification$
BEGIN
    BEGIN
        INSERT INTO audit_logs (
            id, actor_type, actor_subject, action, outcome, request_id,
            allowed_target_id, metadata
        ) VALUES (
            '40000000-0000-4000-8000-000000000054', 'USER', 'subject:user',
            'ALLOW_TARGET_DISABLED', 'SUCCESS',
            '50000000-0000-4000-8000-000000000054',
            '10000000-0000-4000-8000-000000000032', '{"enabled":false}'
        );
        RAISE EXCEPTION 'non-admin allowed-target audit event was accepted';
    EXCEPTION
        WHEN check_violation THEN NULL;
    END;

    BEGIN
        DELETE FROM allowed_targets
         WHERE id = '10000000-0000-4000-8000-000000000032';
        RAISE EXCEPTION 'audited allowed target was hard deleted';
    EXCEPTION
        WHEN foreign_key_violation THEN NULL;
    END;
END
$verification$;

ROLLBACK;

SELECT 'database verification passed' AS result;
