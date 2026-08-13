# Day 20 — History and frontend checkpoint

Day 20 completes the first usable SecureScan frontend journey: a user can
submit a scan, follow its lifecycle, revisit it from durable history, and
filter recent history by status.

## Delivered behavior

- `/history` loads the newest 100 durable jobs through `GET /api/v1/scans`.
- The status control filters queued, accepted, running, completed, failed, and
  blocked jobs without another request.
- Every target and `View scan` action links to the encoded `/scans/{id}` route.
- History and detail timestamps use one deterministic `en-GB` UTC formatter.
- Loading, empty, no-match, API failure, request ID, and retry states are
  explicit and accessible.
- The existing form and polling journey remains unchanged: successful form
  submission redirects to detail, active jobs poll without overlapping
  requests, and polling stops at terminal status or unmount.

The first 100 jobs are intentionally described as **recent scans**. The public
API already supports keyset cursors; loading additional pages is deferred until
the product needs more than this bounded checkpoint view.

## Browser-to-API boundary

The browser now calls the same-origin `NEXT_PUBLIC_API_BASE_URL=/backend` path.
Next.js rewrites it to the server-side `BALLERINA_API_BASE_URL`. This prevents
local development from depending on a permissive cross-origin Ballerina policy
and keeps the internal service origin out of browser code.

Development configuration:

```dotenv
NEXT_PUBLIC_API_BASE_URL=/backend
BALLERINA_API_BASE_URL=http://127.0.0.1:9090
```

WSO2 API Manager can replace `BALLERINA_API_BASE_URL` at the gateway stage
without changing components or the typed API client.

## Automated verification

Run from `frontend/` after copying `.env.example` to `.env.local`:

```bash
npm test
npm run typecheck
npm run lint
npm run build
```

Focused frontend coverage includes:

- invalid form target, port, and authorization confirmation;
- normalized successful form submission and server error correlation IDs;
- all public status labels and active/terminal progress behavior;
- queued → running → completed polling and terminal stop behavior;
- temporary retry, manual retry, unmount abort, Strict Mode, and ID changes;
- history loading, UTC timestamps, encoded detail links, filters, empty data,
  API errors, and retry.

The wider service checks are:

```bash
cd scanner-engine && GOCACHE=/tmp/securescan-go-cache go test ./...
cd ballerina-api && JAVA_HOME=/usr/lib/jvm/java-21-openjdk bal test
cd database && ./scripts/verify.sh
```

The database verification command requires a running PostgreSQL instance with
the development schema and credentials described in `database/README.md`.

## Manual checkpoint

The same-origin request path was exercised locally through
`Next.js → Ballerina → Go`. An authorized scan of the local development Go
listener was accepted, polled to `completed`, and returned port `8081` as open.
The run used an explicit local allowlist and private-target development override;
those settings must never be production defaults.

The PostgreSQL-backed history leg was not live-run in the checkpoint environment
because it had no Docker daemon or PostgreSQL server. The repository retains
the versioned migrations, database verification SQL, parameterized persistence
queries, and Ballerina history projection tests. A complete local acceptance
run therefore still requires:

1. Start PostgreSQL and apply/verify migrations.
2. Start Go with the exact authorized target in `ALLOWED_TARGETS`.
3. Start Ballerina with `persistenceEnabled=true`.
4. Start Next.js with the same-origin proxy settings above.
5. Submit a scan, wait for a terminal status, open `/history`, filter its status,
   and revisit the detail route.

Do not commit `.env.local`, database passwords, identity tokens, or expanded
private-target settings.
