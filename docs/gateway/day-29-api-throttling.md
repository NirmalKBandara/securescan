# Day 29: API throttling and security limits

Day 29 adds fail-closed traffic and workload limits at the API Manager,
Next.js, Ballerina, and scanner boundaries. The limits are deliberately
duplicated: API Manager protects shared capacity, while application-side hard
caps remain effective if a trusted internal caller reaches Ballerina or the
scanner without passing through the public Gateway.

## Enforced limits

| Control | Enforcement | Result |
| --- | --- | --- |
| Ordinary application quota | `SecureScanUser`: 60 requests/minute and 10 requests/second | Gateway `429` after quota exhaustion |
| Administrator application quota | `SecureScanAdmin`: 120 requests/minute and 20 requests/second | Gateway `429` after quota exhaustion |
| Concurrent work | One `QUEUED` or `RUNNING` scan per authenticated owner | API `429 JOB_LIMIT_REACHED`, with `Retry-After: 5` |
| Port range | At most 1,000 inclusive ports per scan | API `400 INVALID_PORT_RANGE` |
| Request body | At most 4,096 bytes | Proxy or API `413 REQUEST_TOO_LARGE` |
| Gateway/backend wait | 10 seconds, no retry | Safe frontend `504 API_GATEWAY_TIMEOUT` |
| Direct backend access | Trusted Gateway secret and derived identity are required | Ballerina `401` without the trusted hop |

Environment values may tighten the application limits but cannot raise them.
Ballerina refuses to start unless `maxActiveScansPerOwner` is exactly one, and
rejects a port or body limit above its hard cap. The scanner also rejects
`MAX_PORTS_PER_SCAN` values above 1,000.

The one-active-scan check is performed inside the PostgreSQL transaction after
acquiring a per-owner advisory lock. Concurrent requests for the same owner are
therefore serialized before the active-row count and insert; sending requests
in parallel cannot bypass the limit. Administrators receive a larger Gateway
request quota, but do not receive a larger per-owner scan-work quota.

## Install the subscription policies

Complete the Day 27 API import and Day 28 Identity Server key-manager and
Developer Portal setup first. Obtain a short-lived API Manager Admin REST API
token with permission to manage throttling policies, then run:

```sh
export WSO2_APIM_ADMIN_TOKEN='<short-lived-redacted-token>'
deployment/apim/configure-throttling.sh
```

The script creates `SecureScanUser` and `SecureScanAdmin` only when a policy of
the same name does not already exist. For local self-signed development only,
`WSO2_APIM_INSECURE=true` enables curl's certificate bypass. Prefer trusting
the development CA and never use that switch in a shared environment.

In Developer Portal, subscribe the ordinary frontend application with
`SecureScanUser`. Use `SecureScanAdmin` only for a separately controlled
administrator application whose identities carry `securescan-admin`. Do not
attach `Unlimited` to either application. Re-import the API Controller project,
create a new revision, deploy it to the `Default` Gateway, and confirm schema
validation and both subscription policies are present.

## Request size and timeout configuration

The supported frontend settings are:

```dotenv
API_MAX_REQUEST_BYTES=4096
API_GATEWAY_TIMEOUT_MS=10000
```

Both are server-only values. Lower values are permitted; values above the hard
caps make the Next.js proxy fail closed. The imported API project applies a
10-second production endpoint timeout, selects `fault` on timeout, and disables
automatic retries so a timed-out scan creation is not submitted twice.

Ballerina counts the actual bytes read before parsing JSON. It does not trust a
missing or forged `Content-Length`. API Manager schema validation and frontend
Zod validation improve feedback, but Ballerina and the scanner remain the
authoritative workload boundary.

## API versioning behavior

`SecureScanAPI` remains version `1.0.0` at context `/securescan/v1`. Throttling,
timeouts, and stricter abuse-prevention limits do not change successful v1
request or response shapes, so Day 29 is deployed as a new revision of v1, not
as a new API version.

Future compatible v1 changes must keep the current fields and public error
envelope, may add optional response fields, and are deployed as revisions.
Removing or renaming fields, changing their meaning, or making optional input
required needs a new major context such as `/securescan/v2`. Existing v1
subscriptions are not silently migrated to v2. The old version remains
published during a documented migration window and is retired only after its
subscribers have moved.

## Live acceptance

Use only a hostname or address that the operator owns or is explicitly
authorized to scan. Use a clean ordinary-user application with no active scan.
Set a short-lived access token and run:

```sh
export SECURESCAN_GATEWAY_TOKEN='<short-lived-redacted-token>'
export SECURESCAN_TEST_TARGET='<authorized-test-target>'
deployment/apim/verify-security-limits.sh
```

The script verifies an allowed request, rejects a 1,001-port request, rejects
an oversized body, accepts one long scan and rejects the immediate second scan,
drives the Gateway to `429`, and confirms a direct unauthenticated Ballerina
request is `401`. The test intentionally creates a real 1,000-port scan and
must never be pointed at an unapproved target.

After the policy window resets, repeat an allowed Gateway request and confirm
it succeeds. Then sign in through the frontend and verify its accessible alert
shows a safe throttling message without reflecting the WSO2 response body. A
server-side test already proves that `Retry-After` is retained when the Gateway
supplies it.

Capture and redact:

- the application subscription and selected user/admin policy;
- Gateway analytics or logs for an allowed request and quota `429`;
- the safe frontend throttling alert and correlation ID;
- Ballerina evidence for the first accepted scan and second owner-limited `429`;
- the 1,001-port, oversized-body, timeout, and direct-backend results;
- a successful request after the quota window recovers.

Never capture access tokens, cookies, client secrets, the backend shared secret,
or unredacted authorization headers.

## Repository verification

```sh
cd frontend
npm test
npm run typecheck
npm run lint

cd ../ballerina-api
JAVA_HOME=/usr/lib/jvm/java-21-openjdk bal test

cd ../scanner-engine
go test ./...

cd ..
bash -n deployment/apim/configure-throttling.sh \
  deployment/apim/verify-security-limits.sh
jq empty deployment/apim/throttling/*.json
```

The repository checks prove that limits cannot be configured above the hard
caps, boundary values behave correctly, Gateway errors remain safe, and policy
artifacts are syntactically valid. This host cannot run Docker or API
Controller, so it cannot produce the live Gateway quota, recovery, browser, or
direct-deployment evidence. Keep Issue #13 open and its project item out of
`Done` until every live acceptance item above is captured.
