DROP INDEX audit_logs_allowed_target_disable_uq;
DROP INDEX audit_logs_allowed_target_creation_uq;

ALTER TABLE audit_logs
    DROP CONSTRAINT audit_logs_allowed_target_metadata_ck,
    DROP CONSTRAINT audit_logs_allowed_target_event_shape_ck,
    DROP CONSTRAINT audit_logs_allowed_target_id_fkey,
    ADD CONSTRAINT audit_logs_allowed_target_id_fkey
        FOREIGN KEY (allowed_target_id)
        REFERENCES allowed_targets(id) ON DELETE SET NULL;

ALTER TABLE allowed_targets
    DROP CONSTRAINT allowed_targets_value_ck,
    DROP CONSTRAINT allowed_targets_kind_ck;

UPDATE allowed_targets SET target_kind = 'CIDR' WHERE target_kind = 'IP';

ALTER TABLE allowed_targets
    ADD CONSTRAINT allowed_targets_kind_ck
        CHECK (target_kind IN ('HOSTNAME', 'CIDR')),
    ADD CONSTRAINT allowed_targets_value_ck CHECK (
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
    );

DROP INDEX allowed_targets_global_hostname_uq;
DROP INDEX allowed_targets_owner_hostname_uq;
DROP INDEX allowed_targets_global_cidr_uq;
DROP INDEX allowed_targets_owner_cidr_uq;
DROP INDEX allowed_targets_active_cidr_gist_idx;

CREATE UNIQUE INDEX allowed_targets_global_hostname_uq
    ON allowed_targets (hostname_normalized, COALESCE(start_port, 0),
                        COALESCE(end_port, 0))
    WHERE scope = 'GLOBAL' AND target_kind = 'HOSTNAME';
CREATE UNIQUE INDEX allowed_targets_owner_hostname_uq
    ON allowed_targets (owner_subject, hostname_normalized,
                        COALESCE(start_port, 0), COALESCE(end_port, 0))
    WHERE scope = 'OWNER' AND target_kind = 'HOSTNAME';
CREATE UNIQUE INDEX allowed_targets_global_cidr_uq
    ON allowed_targets (target_cidr, COALESCE(start_port, 0),
                        COALESCE(end_port, 0))
    WHERE scope = 'GLOBAL' AND target_kind = 'CIDR';
CREATE UNIQUE INDEX allowed_targets_owner_cidr_uq
    ON allowed_targets (owner_subject, target_cidr,
                        COALESCE(start_port, 0), COALESCE(end_port, 0))
    WHERE scope = 'OWNER' AND target_kind = 'CIDR';
CREATE INDEX allowed_targets_active_cidr_gist_idx
    ON allowed_targets USING gist (target_cidr inet_ops)
    WHERE enabled AND target_kind = 'CIDR';
