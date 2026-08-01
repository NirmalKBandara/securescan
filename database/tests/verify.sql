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
    IF (SELECT count(*) FROM schema_migrations) <> 2 THEN
        RAISE EXCEPTION 'expected exactly two applied migrations';
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

SELECT 'database verification passed' AS result;
