# SecureScan frontend

The Day 20 frontend is a Next.js 16 App Router application with strict TypeScript,
plain CSS design tokens, an accessible application shell, a typed boundary for
the Ballerina public API, reusable scan interface components, and validated scan
submission.

## Requirements

- Node.js 20.9 or newer
- npm 10 or newer

## Setup

```bash
cp .env.example .env.local
npm install
npm run dev
```

Open `http://localhost:3000`. `NEXT_PUBLIC_API_BASE_URL` is required in every
environment; the example uses the same-origin `/backend` path. Next.js rewrites
that path to the server-only `BALLERINA_API_BASE_URL`, which defaults to
`http://127.0.0.1:9090`. Set
`NEXT_PUBLIC_LOGIN_URL` to the WSO2 OIDC entry
point once identity integration is available.

## Routes

- `/login` — identity-provider entry page
- `/dashboard` — scan overview and primary action
- `/scans/new` — validated scan submission to the Ballerina public API
- `/scans/[id]` — scan status/results destination
- `/history` — durable scan history with status filtering and UTC timestamps
- `/admin` — administrator controls destination
- `/ui-preview` — backend-free Day 17 component and state review surface

The new-scan, scan-detail, and history pages use the shared `ScanForm`, `ScanStatus`, and
`ResultsTable` components. `ScanForm` uses React Hook Form and Zod to validate
target syntax, port boundaries and ordering, and explicit authorization before
calling `scansApi.create`. Accepted jobs navigate to `/scans/{id}`; history
loads durable newest-first jobs, filters them locally by lifecycle status, and
links every row back to its detail page. Public API
errors and correlation request IDs render in an accessible alert.

`/ui-preview` uses deterministic mock data to show
queued, running, completed, failed, blocked, loading, error, populated-result,
and empty-result states. Its form is deliberately disabled so the preview never
creates a real scan.

## Reusable components

- `ScanForm` — labeled target, port range, and authorization controls
- `ScanStatus` and `StatusBadge` — lifecycle presentation with text and color
- `ResultsTable` — semantic desktop table and responsive mobile result cards
- `ErrorMessage` — alert feedback with optional correlation request ID
- `LoadingState` — text and motion-based progress feedback

Mock data lives in `lib/mocks/scans.ts` and is presentation-only. Components do
not call the backend directly; later pages should continue to use `scansApi`.

## API client

`lib/api/types.ts` mirrors `docs/api/ballerina-public-api.md`, including stable
success/error envelopes, lifecycle states, results and keyset history. Use the
single `scansApi` export instead of calling configured URLs from components.
The boundary preserves public request IDs on `SecureScanApiError` for support.

## Quality checks

```bash
npm test
npm run typecheck
npm run lint
npm run build
```

See `docs/frontend/day-20-history-checkpoint.md` for history behavior, the
same-origin service boundary, integration checks, and test coverage.

Do not commit `.env.local`, tokens, or identity-provider secrets. Only
`NEXT_PUBLIC_*` values intended for browsers belong in this application.
