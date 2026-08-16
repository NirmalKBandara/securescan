# Day 31: strong target authorization and DNS safety

Day 31 makes the database allowlist an enforced scan boundary. A caller's
`authorized` acknowledgement is still required, but it is never treated as
permission by itself. Ballerina now admits a scan only when the complete port
range matches an enabled, unexpired hostname, IP, or CIDR rule that applies to
the authenticated owner.

## Authorization sequence

For every persisted scan request, Ballerina performs this sequence:

1. Authenticate the Gateway identity and validate the request shape and limits.
2. Match the normalized target and complete port range against an enabled
   `allowed_targets` row.
3. For a hostname, resolve every returned address and reject the complete
   request if any answer is unsafe.
4. Persist the queued job with the matched policy identifier.
5. Claim the durable dispatch lease, resolve and authorize the target again,
   and confirm that the same policy is still enabled immediately before the
   scanner call.
6. Dispatch only after the second decision succeeds.

The second decision catches a policy disabled while a job was queued and
narrows the DNS-rebinding window. An allowlisted name is not equivalent to an
allowlisted address: every DNS answer must independently pass the address
safety policy on both resolutions.

## Matching rules

- `HOSTNAME` is an exact, lowercase DNS name. Wildcards, empty labels,
  whitespace, leading or trailing dots, labels over 63 characters, and names
  over 253 characters are rejected.
- `IP` matches only that exact IPv4 or IPv6 address.
- `CIDR` matches an address contained by the stored network.
- A rule's optional port interval must contain the request's complete interval.
- Owner-scoped rules apply only to that owner; otherwise the rule must be
  global.
- Disabled or expired rules never authorize admission or dispatch.

Hostname allowlist matching happens before DNS lookup. This avoids resolving
attacker-selected names that do not have an explicit policy entry.

## Unsafe addresses

The authorization module rejects the complete target when any answer is:

- loopback;
- RFC1918 private or IPv6 unique-local;
- link-local unicast or multicast;
- unspecified;
- multicast; or
- a cloud metadata endpoint, including `169.254.169.254` and
  `fd00:ec2::254`.

The Go scanner retains its own address validation as defense in depth. The
Ballerina policy decision is authoritative for database-managed authorization,
while Go validates again before opening connections.

## Blocked-attempt audit trail

Admission failures create a terminal `BLOCKED` scan and `SCAN_BLOCKED` audit
event transactionally. The event records the owner, actor, public scan ID,
request ID, safe failure code, database timestamp, and the matched policy ID
when one existed. It does not store DNS answers, request bodies, credentials,
or internal resolver errors.

A target that becomes unsafe or loses permission at dispatch is also moved to
`BLOCKED` without a scanner job ID. Migration `V006` permits that blocked row
to retain the matched policy attribution while preserving the invariant that
the scanner was never called.

## Fail-closed configuration

Production startup requires PostgreSQL because the allowlist is the source of
authorization. The only bypass is `targetAuthorizationTestBypass`; startup
accepts it solely for the fixed isolated Ballerina test service and mock scanner
configuration. It cannot be enabled for a deployable service configuration.

## Verification

Run the Ballerina contract suite:

```sh
cd ballerina-api
JAVA_HOME=/usr/lib/jvm/java-21-openjdk bal test
```

The suite covers authorized public targets, strict hostname validation, private
and unsafe DNS answers, missing rules, and disabled rules. It uses pure policy
helpers for deterministic DNS-answer cases; it does not depend on public DNS.

Run the PostgreSQL migration and rollback-only verification on a Docker-capable
host:

```sh
docker compose -f deployment/compose.yaml up -d --wait postgres
./database/scripts/migrate.sh up
./database/scripts/verify.sh
```

The database checks prove exact hostname/IP/CIDR and port containment,
disabled-rule rejection, unsafe network classification, blocked-job policy
attribution, and the paired `SCAN_BLOCKED` audit event.

## Acceptance result

Repository verification passes for all deterministic checks: authorized public
targets pass; unauthorized names, private addresses, unsafe DNS answers, and
disabled rules fail closed; blocked attempts are auditable. Live DNS transition
and end-to-end Gateway evidence still require the documented local WSO2 and
PostgreSQL runtime.
