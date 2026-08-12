# Day 19 — Scan details and polling

Day 19 connects the scan detail route to the Ballerina public API. The page
loads the durable job, polls while work is active, displays terminal results or
safe failure information, and releases all polling resources when they are no
longer needed.

## Detail lifecycle

1. `/scans/{id}` renders a loading state and requests
   `GET /api/v1/scans/{scanId}`.
2. `queued`, `accepted`, and `running` responses schedule exactly one follow-up
   request after two seconds.
3. `completed`, `failed`, and `blocked` responses are terminal and do not
   schedule another poll.
4. Changing the scan ID or leaving the page clears the timer and aborts any
   in-flight request.

The polling hook owns its timer and abort controller inside each React effect
generation. This prevents stale requests, route changes, manual retries, and
React Strict Mode effect replay from creating duplicate polling loops.

## Results and outcomes

The page always shows the target, port range, status, creation time, and last
update time. A completed scan displays every returned address and port with its
`open` or `closed` state. A completed scan with no findings displays an explicit
empty result state.

Failed and blocked jobs display only allowlisted explanations derived from the
public `failureCode`. Raw scanner diagnostics remain behind the Ballerina
boundary. The public API now preserves `blocked` as a distinct terminal status
and includes its persisted safe failure code in scan detail responses.

## Temporary failures and retry

Network errors, HTTP `408`, `429`, and `5xx` responses are treated as temporary.
The page retains the last successful scan state, tells the user the update is
delayed, and automatically retries after the normal polling interval. A manual
retry cancels the scheduled generation before starting a new request. Other
HTTP failures stop automatic retry but remain manually retryable.

## Local verification

Start the backend services, configure `NEXT_PUBLIC_API_BASE_URL`, and run:

```bash
cd frontend
npm run dev
```

Create an authorized scan and open its returned `/scans/{id}` route. Confirm
that the status progresses from queued/running to a terminal state, that only
one detail request is active at a time, and that requests stop after completion
or navigation away from the page.

## Automated checks

```bash
cd frontend
npm test
npm run typecheck
npm run lint
NEXT_PUBLIC_API_BASE_URL=http://localhost:9090 npm run build

cd ../ballerina-api
JAVA_HOME=/usr/lib/jvm/java-21-openjdk bal test
```

The frontend tests cover completed timestamps and open/closed findings, active
status progression, terminal polling stop, safe failed and blocked reasons,
automatic and manual retry, timer cleanup, request abort, React Strict Mode,
and scan ID changes. The Ballerina suite covers the durable blocked projection
and safe failure-code response in addition to the existing public API tests.
