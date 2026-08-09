# Day 16 — Next.js frontend foundation

Day 16 establishes the browser application boundary without pulling forward
the reusable components, forms, polling, or authentication work scheduled for
later days.

## Technology choices

- Next.js 16 App Router and React 19
- Strict TypeScript with the Next.js type-checking plugin
- Plain CSS with design tokens, responsive breakpoints, visible focus styles,
  and reduced-motion support
- ESLint with the Next.js Core Web Vitals and TypeScript configurations
- npm lockfile for reproducible installs

The dependency set was upgraded from the initially generated Next.js 14
scaffold after npm reported a known high-severity vulnerability. The committed
Next.js 16 dependency graph reported zero known vulnerabilities when installed.

## Application boundary

`NEXT_PUBLIC_API_BASE_URL` is mandatory and must be an absolute HTTP or HTTPS
URL. It is validated once in `frontend/lib/env.ts`; pages and components do not
hard-code service locations. `NEXT_PUBLIC_LOGIN_URL` is optional until WSO2 is
integrated and defaults to the dashboard.

`frontend/lib/api` mirrors the public Ballerina contract for scan creation,
detail, results, history, lifecycle states, stable error codes, and request
correlation IDs. All later frontend API calls should use `scansApi` instead of
calling `fetch` directly from UI components.

## Routes

| Route | Day 16 responsibility |
| --- | --- |
| `/login` | Identity-provider entry placeholder |
| `/dashboard` | Overview and primary scan action |
| `/scans/new` | Accessible form-layout preview |
| `/scans/[id]` | Typed dynamic scan-detail destination |
| `/history` | Durable-history empty state |
| `/admin` | Allowed-target and audit placeholders |

The root route redirects to `/dashboard`, and the application includes a custom
not-found page.

## Accessibility foundation

The shared shell uses semantic header, navigation, main, and footer landmarks.
It includes a keyboard-visible skip link, descriptive navigation labels,
associated form labels, visible focus treatment, sufficient color contrast,
mobile reflow, and reduced-motion behavior. Disabled form controls clearly
identify the Day 18 submission boundary rather than presenting a non-functional
active form.

## Local verification

```bash
cd frontend
cp .env.example .env.local
npm install
npm run typecheck
npm run lint
npm run build
```

Day 16 acceptance evidence:

- strict TypeScript check passed
- ESLint passed with the Core Web Vitals configuration
- the optimized production build passed
- the build emitted `/login`, `/dashboard`, `/scans/new`, `/scans/[id]`,
  `/history`, and `/admin`
- npm reported zero known vulnerabilities after the patched dependency upgrade
- `git diff --check` passed
