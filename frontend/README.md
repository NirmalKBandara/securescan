# SecureScan frontend

The Day 16 frontend is a Next.js 16 App Router application with strict TypeScript,
plain CSS design tokens, an accessible application shell, and a typed boundary
for the Ballerina public API.

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
environment; the example points development at `http://localhost:9090`. Set
`NEXT_PUBLIC_LOGIN_URL` to the WSO2 OIDC entry
point once identity integration is available.

## Routes

- `/login` — identity-provider entry page
- `/dashboard` — scan overview and primary action
- `/scans/new` — accessible scan-form preview
- `/scans/[id]` — scan status/results destination
- `/history` — durable scan history destination
- `/admin` — administrator controls destination

The pages intentionally contain presentation/empty states only on Day 16.
Reusable states arrive on Day 17 and submission wiring on Day 18.

## API client

`lib/api/types.ts` mirrors `docs/api/ballerina-public-api.md`, including stable
success/error envelopes, lifecycle states, results and keyset history. Use the
single `scansApi` export instead of calling configured URLs from components.
The boundary preserves public request IDs on `SecureScanApiError` for support.

## Quality checks

```bash
npm run typecheck
npm run lint
npm run build
```

Do not commit `.env.local`, tokens, or identity-provider secrets. Only
`NEXT_PUBLIC_*` values intended for browsers belong in this application.
