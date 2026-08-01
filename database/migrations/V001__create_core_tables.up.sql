CREATE TABLE allowed_targets (
    id                  uuid PRIMARY KEY,
    target_kind         text NOT NULL,
    hostname_normalized text,
    target_cidr         cidr,
    scope               text NOT NULL DEFAULT 'GLOBAL',
    owner_subject       text,
    start_port          integer,
    end_port            integer,
    enabled             boolean NOT NULL DEFAULT true,
    expires_at          timestamptz,
    created_by_subject  text NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT allowed_targets_kind_ck
        CHECK (target_kind IN ('HOSTNAME', 'CIDR')),
    CONSTRAINT allowed_targets_value_ck CHECK (
        (target_kind = 'HOSTNAME'
            AND hostname_normalized IS NOT NULL
            AND target_cidr IS NULL
            AND hostname_normalized = lower(hostname_normalized)
            AND hostname_normalized = btrim(hostname_normalized)
            AND length(hostname_normalized) BETWEEN 1 AND 253)
        OR
        (target_kind = 'CIDR'
            AND hostname_normalized IS NULL
            AND target_cidr IS NOT NULL)
    ),
    CONSTRAINT allowed_targets_scope_ck
        CHECK (scope IN ('GLOBAL', 'OWNER')),
    CONSTRAINT allowed_targets_owner_ck CHECK (
        (scope = 'GLOBAL' AND owner_subject IS NULL)
        OR (scope = 'OWNER' AND owner_subject IS NOT NULL
            AND length(owner_subject) BETWEEN 1 AND 255)
    ),
    CONSTRAINT allowed_targets_ports_ck CHECK (
        (start_port IS NULL AND end_port IS NULL)
        OR (start_port IS NOT NULL
            AND end_port IS NOT NULL
            AND start_port BETWEEN 1 AND 65535
            AND end_port BETWEEN 1 AND 65535
            AND start_port <= end_port)
    ),
    CONSTRAINT allowed_targets_creator_ck
        CHECK (length(created_by_subject) BETWEEN 1 AND 255),
    CONSTRAINT allowed_targets_expiry_ck
        CHECK (expires_at IS NULL OR expires_at > created_at)
);

CREATE TABLE scan_jobs (
    id                  uuid PRIMARY KEY,
    scanner_scan_id     uuid UNIQUE,
    owner_subject       text NOT NULL,
    target              text NOT NULL,
    start_port          integer NOT NULL,
    end_port            integer NOT NULL,
    status              text NOT NULL,
    allowed_target_id   uuid REFERENCES allowed_targets(id) ON DELETE SET NULL,
    failure_code        text,
    duration_nanos      bigint,
    created_at          timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at          timestamptz,
    finished_at         timestamptz,

    CONSTRAINT scan_jobs_owner_ck
        CHECK (length(owner_subject) BETWEEN 1 AND 255),
    CONSTRAINT scan_jobs_target_ck
        CHECK (length(btrim(target)) BETWEEN 1 AND 253),
    CONSTRAINT scan_jobs_ports_ck CHECK (
        start_port BETWEEN 1 AND 65535
        AND end_port BETWEEN 1 AND 65535
        AND start_port <= end_port
    ),
    CONSTRAINT scan_jobs_status_ck CHECK (
        status IN ('QUEUED', 'RUNNING', 'COMPLETED', 'FAILED', 'BLOCKED')
    ),
    CONSTRAINT scan_jobs_failure_ck CHECK (
        (status IN ('FAILED', 'BLOCKED') AND failure_code IS NOT NULL)
        OR (status NOT IN ('FAILED', 'BLOCKED') AND failure_code IS NULL)
    ),
    CONSTRAINT scan_jobs_timeline_ck CHECK (
        updated_at >= created_at
        AND (started_at IS NULL OR started_at >= created_at)
        AND (finished_at IS NULL OR finished_at >= created_at)
        AND (finished_at IS NULL OR started_at IS NULL
             OR finished_at >= started_at)
        AND (status = 'QUEUED' AND started_at IS NULL
                                 AND finished_at IS NULL
             OR status = 'RUNNING' AND started_at IS NOT NULL
                                    AND finished_at IS NULL
             OR status = 'COMPLETED' AND started_at IS NOT NULL
                                      AND finished_at IS NOT NULL
             OR status = 'FAILED' AND finished_at IS NOT NULL
             OR status = 'BLOCKED' AND started_at IS NULL
                                    AND finished_at IS NOT NULL)
    ),
    CONSTRAINT scan_jobs_scanner_id_ck CHECK (
        status NOT IN ('RUNNING', 'COMPLETED') OR scanner_scan_id IS NOT NULL
    ),
    CONSTRAINT scan_jobs_blocked_ck CHECK (
        status <> 'BLOCKED'
        OR (scanner_scan_id IS NULL AND allowed_target_id IS NULL)
    ),
    CONSTRAINT scan_jobs_duration_ck CHECK (
        (status = 'COMPLETED' AND duration_nanos IS NOT NULL
                              AND duration_nanos >= 0)
        OR (status <> 'COMPLETED' AND duration_nanos IS NULL)
    )
);

CREATE TABLE scan_results (
    scan_job_id uuid NOT NULL
        REFERENCES scan_jobs(id) ON DELETE CASCADE,
    address     inet NOT NULL,
    port        integer NOT NULL,
    state       text NOT NULL,
    observed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (scan_job_id, address, port),
    CONSTRAINT scan_results_port_ck CHECK (port BETWEEN 1 AND 65535),
    CONSTRAINT scan_results_state_ck CHECK (state IN ('OPEN', 'CLOSED'))
);

CREATE TABLE audit_logs (
    id                uuid PRIMARY KEY,
    occurred_at       timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor_type        text NOT NULL,
    actor_subject     text,
    owner_subject     text,
    action            text NOT NULL,
    outcome           text NOT NULL,
    request_id        uuid,
    scan_job_id       uuid REFERENCES scan_jobs(id) ON DELETE SET NULL,
    allowed_target_id uuid REFERENCES allowed_targets(id) ON DELETE SET NULL,
    metadata          jsonb NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT audit_logs_actor_type_ck
        CHECK (actor_type IN ('USER', 'ADMIN', 'SERVICE', 'SYSTEM')),
    CONSTRAINT audit_logs_actor_ck CHECK (
        (actor_type = 'SYSTEM' AND actor_subject IS NULL)
        OR (actor_type <> 'SYSTEM' AND actor_subject IS NOT NULL
            AND length(actor_subject) BETWEEN 1 AND 255)
    ),
    CONSTRAINT audit_logs_owner_ck CHECK (
        owner_subject IS NULL OR length(owner_subject) BETWEEN 1 AND 255
    ),
    CONSTRAINT audit_logs_action_ck CHECK (action IN (
        'SCAN_REQUESTED', 'SCAN_BLOCKED', 'SCAN_DISPATCHED',
        'SCAN_STARTED', 'SCAN_COMPLETED', 'SCAN_FAILED', 'SCAN_VIEWED',
        'ALLOW_TARGET_CREATED', 'ALLOW_TARGET_UPDATED',
        'ALLOW_TARGET_DISABLED'
    )),
    CONSTRAINT audit_logs_outcome_ck
        CHECK (outcome IN ('SUCCESS', 'DENIED', 'FAILURE')),
    CONSTRAINT audit_logs_metadata_object_ck
        CHECK (jsonb_typeof(metadata) = 'object')
);
