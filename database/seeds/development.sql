-- Deterministic, credential-free fixtures for local development only.
INSERT INTO allowed_targets (
    id, target_kind, hostname_normalized, scope, start_port, end_port,
    created_by_subject
) VALUES (
    '10000000-0000-4000-8000-000000000001',
    'HOSTNAME',
    'scan.dev.example',
    'GLOBAL',
    80,
    443,
    'system:development-seed'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO allowed_targets (
    id, target_kind, target_cidr, scope, start_port, end_port,
    created_by_subject
) VALUES (
    '10000000-0000-4000-8000-000000000002',
    'CIDR',
    '192.0.2.0/24',
    'GLOBAL',
    80,
    443,
    'system:development-seed'
)
ON CONFLICT (id) DO NOTHING;
