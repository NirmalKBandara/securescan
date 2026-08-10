# Day 17 — Reusable UI states and components

Day 17 replaces the Day 16 scan placeholders with reusable, typed presentation
components. The components remain independent of the Ballerina service so all
required states can be reviewed before submission and polling are connected.

## Components

| Component | Responsibility |
| --- | --- |
| `ScanForm` | Labeled target, start/end port, and explicit authorization controls |
| `ScanStatus` | Target, port range, timestamps, lifecycle badge, and active progress |
| `ResultsTable` | Populated scan findings and a clear empty-results state |
| `StatusBadge` | Text-and-color treatment for every public lifecycle state |
| `ErrorMessage` | Screen-reader-announced failure details and optional request ID |
| `LoadingState` | Screen-reader-announced loading feedback with reduced-motion support |

`/scans/new` now renders `ScanForm`, while `/scans/[id]` composes `ScanStatus`
and `ResultsTable`. These pages still use mock values and do not call the API;
that separation keeps Day 18 submission and Day 19 polling work explicit.

## Backend-free review surface

Open `/ui-preview` to review deterministic mock examples of:

- queued and running jobs with progress feedback
- completed, failed, and blocked jobs
- loading and scanner-unavailable feedback
- populated results with open and closed ports
- an empty result set
- the disabled Day 17 scan-form preview

The preview route is deliberately not part of the primary application
navigation. It is a development and review surface, not a user workflow.

## Accessibility and responsive behavior

- Every form field has a persistent label; helper text is associated with the
  target field using `aria-describedby`.
- Authorization uses a full clickable checkbox label and explicit permission
  language.
- Status badges include visible text and never rely on color alone.
- Active scans use a named progressbar and a polite live region.
- Loading uses `role="status"`; errors use `role="alert"` and can expose the
  safe public request ID for support.
- Results use a real table with a caption and scoped column headers. Below
  560px, each row reflows into labeled fields without changing the DOM table
  semantics.
- Hostnames, addresses, and identifiers wrap instead of overflowing cards.
- Animations are enabled only when the user has not requested reduced motion.
- Existing visible focus styles, skip navigation, and 44px button targets are
  preserved.

## Acceptance evidence

Run from `frontend/`:

```bash
npm run typecheck
npm run lint
NEXT_PUBLIC_API_BASE_URL=http://localhost:9090 \
  NEXT_PUBLIC_LOGIN_URL=/dashboard npm run build
```

Then open `/ui-preview` at desktop and narrow mobile widths and keyboard through
the page. Day 17 verification completed with:

- strict TypeScript check passed
- ESLint passed
- optimized Next.js production build passed
- the build emitted the new static `/ui-preview` route
- every required lifecycle, loading, and empty state is present in mock data
- `git diff --check` passed

No React Hook Form, Zod, API submission, polling, or backend-driven history was
added because those are Days 18–20 responsibilities.
