BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version    text PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO schema_migrations (version)
VALUES
    ('V001__create_core_tables'),
    ('V002__create_core_indexes'),
    ('V003__add_scan_dispatch_lease'),
    ('V004__harden_scan_audit_events'),
    ('V005__complete_allowed_target_administration'),
    ('V006__enforce_target_authorization')
ON CONFLICT (version) DO NOTHING;

COMMIT;
