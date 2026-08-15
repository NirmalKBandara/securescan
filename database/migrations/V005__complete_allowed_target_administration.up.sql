DROP INDEX allowed_targets_global_hostname_uq;
DROP INDEX allowed_targets_owner_hostname_uq;
DROP INDEX allowed_targets_global_cidr_uq;
DROP INDEX allowed_targets_owner_cidr_uq;
DROP INDEX allowed_targets_active_cidr_gist_idx;

ALTER TABLE allowed_targets
    DROP CONSTRAINT allowed_targets_value_ck,
    DROP CONSTRAINT allowed_targets_kind_ck,
    ADD CONSTRAINT allowed_targets_kind_ck
        CHECK (target_kind IN ('HOSTNAME', 'IP', 'CIDR')),
    ADD CONSTRAINT allowed_targets_value_ck CHECK (
        (target_kind = 'HOSTNAME'
            AND hostname_normalized IS NOT NULL
            AND target_cidr IS NULL
            AND hostname_normalized = lower(hostname_normalized)
            AND hostname_normalized = btrim(hostname_normalized)
            AND length(hostname_normalized) BETWEEN 1 AND 253)
        OR
        (target_kind IN ('IP', 'CIDR')
            AND hostname_normalized IS NULL
            AND target_cidr IS NOT NULL
            AND (target_kind <> 'IP'
                 OR masklen(target_cidr) IN (32, 128)))
    );

CREATE UNIQUE INDEX allowed_targets_global_hostname_uq
    ON allowed_targets (hostname_normalized, COALESCE(start_port, 0),
                        COALESCE(end_port, 0))
    WHERE enabled AND scope = 'GLOBAL' AND target_kind = 'HOSTNAME';
CREATE UNIQUE INDEX allowed_targets_owner_hostname_uq
    ON allowed_targets (owner_subject, hostname_normalized,
                        COALESCE(start_port, 0), COALESCE(end_port, 0))
    WHERE enabled AND scope = 'OWNER' AND target_kind = 'HOSTNAME';
CREATE UNIQUE INDEX allowed_targets_global_cidr_uq
    ON allowed_targets (target_cidr, COALESCE(start_port, 0),
                        COALESCE(end_port, 0))
    WHERE enabled AND scope = 'GLOBAL' AND target_kind IN ('IP', 'CIDR');
CREATE UNIQUE INDEX allowed_targets_owner_cidr_uq
    ON allowed_targets (owner_subject, target_cidr,
                        COALESCE(start_port, 0), COALESCE(end_port, 0))
    WHERE enabled AND scope = 'OWNER' AND target_kind IN ('IP', 'CIDR');
CREATE INDEX allowed_targets_active_cidr_gist_idx
    ON allowed_targets USING gist (target_cidr inet_ops)
    WHERE enabled AND target_kind IN ('IP', 'CIDR');

ALTER TABLE audit_logs
    DROP CONSTRAINT audit_logs_allowed_target_id_fkey,
    ADD CONSTRAINT audit_logs_allowed_target_id_fkey
        FOREIGN KEY (allowed_target_id)
        REFERENCES allowed_targets(id) ON DELETE RESTRICT,
    ADD CONSTRAINT audit_logs_allowed_target_event_shape_ck CHECK (
        action NOT IN (
            'ALLOW_TARGET_CREATED', 'ALLOW_TARGET_UPDATED',
            'ALLOW_TARGET_DISABLED'
        )
        OR (
            actor_type = 'ADMIN'
            AND actor_subject IS NOT NULL
            AND owner_subject IS NULL
            AND outcome = 'SUCCESS'
            AND request_id IS NOT NULL
            AND scan_job_id IS NULL
            AND allowed_target_id IS NOT NULL
        )
    ),
    ADD CONSTRAINT audit_logs_allowed_target_metadata_ck CHECK (
        CASE action
            WHEN 'ALLOW_TARGET_CREATED' THEN
                metadata ?& ARRAY['targetKind', 'target']
                AND metadata - 'targetKind' - 'target' = '{}'::jsonb
                AND metadata ->> 'targetKind' IN ('HOSTNAME', 'IP', 'CIDR')
                AND jsonb_typeof(metadata -> 'target') = 'string'
            WHEN 'ALLOW_TARGET_UPDATED' THEN
                metadata ?& ARRAY['targetKind', 'target']
                AND metadata - 'targetKind' - 'target' = '{}'::jsonb
                AND metadata ->> 'targetKind' IN ('HOSTNAME', 'IP', 'CIDR')
                AND jsonb_typeof(metadata -> 'target') = 'string'
            WHEN 'ALLOW_TARGET_DISABLED' THEN
                metadata = '{"enabled": false}'::jsonb
            ELSE true
        END
    );

CREATE UNIQUE INDEX audit_logs_allowed_target_creation_uq
    ON audit_logs (allowed_target_id)
    WHERE action = 'ALLOW_TARGET_CREATED';
CREATE UNIQUE INDEX audit_logs_allowed_target_disable_uq
    ON audit_logs (allowed_target_id)
    WHERE action = 'ALLOW_TARGET_DISABLED';
