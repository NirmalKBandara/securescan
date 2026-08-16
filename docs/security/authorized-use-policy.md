# SecureScan authorized-use policy

SecureScan may scan only systems that the operator owns or has explicit written
permission to test. A checkbox, application role, or allowed-target row does not
replace that permission.

Before an administrator enables a target, retain an approval record that names:

- the legal owner and authorizing contact;
- exact hostnames, IP addresses, or CIDR ranges;
- permitted ports and test techniques;
- the approved start/end time and timezone;
- rate, concurrency, and source-address expectations; and
- incident and stop-work contacts.

## Prohibited use

Do not use SecureScan to scan third-party infrastructure without permission,
evade access controls or rate limits, discover internal/cloud metadata services,
hide the source of activity, or continue after authorization expires or is
withdrawn. Do not broaden a hostname, CIDR, port range, or time window beyond
the written scope.

Targets resolving to loopback, private, link-local, multicast, unspecified,
cloud metadata, carrier-grade NAT, benchmarking, documentation, or reserved
address space are blocked by the application/scanner policy. Attempting to
bypass these controls is prohibited even in a development environment.

## Administrator responsibilities

Administrators must verify the approval record before creating a rule, use the
narrowest target and port range, disable expired or withdrawn permission
promptly, review blocked/failed jobs and audit events, protect administrator
credentials, and never share the Gateway secret.

## Stop and report

Stop scanning immediately if the owner requests it, a target resolves outside
scope, unexpected service impact occurs, or authorization is uncertain. Disable
the policy rule, preserve request/job correlation IDs and audit evidence, and
notify the authorizing and security contacts. Do not retry until the owner has
confirmed that work may resume.

## Data handling

Scan targets, results, owner identifiers, and audit records may be sensitive.
Grant access by least privilege, retain them only for the documented project
purpose and period, and remove them using the approved retention process.
Never place credentials, tokens, raw request bodies, or private diagnostic data
in issue reports, screenshots, audit metadata, or demonstration recordings.

Unauthorized scanning may violate law, contracts, provider terms, or acceptable
use policies. The operator is responsible for obtaining permission and obeying
all applicable requirements.
