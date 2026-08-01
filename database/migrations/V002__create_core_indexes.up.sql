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

CREATE INDEX scan_jobs_owner_created_idx
    ON scan_jobs (owner_subject, created_at DESC, id DESC);
CREATE INDEX scan_jobs_owner_status_created_idx
    ON scan_jobs (owner_subject, status, created_at DESC, id DESC);
CREATE INDEX scan_jobs_created_idx
    ON scan_jobs (created_at DESC, id DESC);
CREATE INDEX scan_jobs_status_created_idx
    ON scan_jobs (status, created_at DESC, id DESC);
CREATE INDEX scan_jobs_queued_idx
    ON scan_jobs (created_at, id) WHERE status = 'QUEUED';
CREATE INDEX scan_jobs_allowed_target_idx
    ON scan_jobs (allowed_target_id) WHERE allowed_target_id IS NOT NULL;

CREATE INDEX scan_results_open_idx
    ON scan_results (scan_job_id, port, address) WHERE state = 'OPEN';

CREATE INDEX allowed_targets_active_hostname_idx
    ON allowed_targets (hostname_normalized, scope, owner_subject)
    WHERE enabled AND target_kind = 'HOSTNAME';
CREATE INDEX allowed_targets_active_cidr_gist_idx
    ON allowed_targets USING gist (target_cidr inet_ops)
    WHERE enabled AND target_kind = 'CIDR';
CREATE INDEX allowed_targets_expiry_idx
    ON allowed_targets (expires_at) WHERE enabled AND expires_at IS NOT NULL;
CREATE INDEX allowed_targets_created_idx
    ON allowed_targets (created_at DESC, id DESC);

CREATE INDEX audit_logs_occurred_idx
    ON audit_logs (occurred_at DESC, id DESC);
CREATE INDEX audit_logs_action_occurred_idx
    ON audit_logs (action, occurred_at DESC, id DESC);
CREATE INDEX audit_logs_actor_occurred_idx
    ON audit_logs (actor_subject, occurred_at DESC, id DESC)
    WHERE actor_subject IS NOT NULL;
CREATE INDEX audit_logs_owner_occurred_idx
    ON audit_logs (owner_subject, occurred_at DESC, id DESC)
    WHERE owner_subject IS NOT NULL;
CREATE INDEX audit_logs_request_idx
    ON audit_logs (request_id, occurred_at) WHERE request_id IS NOT NULL;
CREATE INDEX audit_logs_scan_job_idx
    ON audit_logs (scan_job_id, occurred_at) WHERE scan_job_id IS NOT NULL;
CREATE INDEX audit_logs_allowed_target_idx
    ON audit_logs (allowed_target_id, occurred_at)
    WHERE allowed_target_id IS NOT NULL;
