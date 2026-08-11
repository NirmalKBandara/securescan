# Day 18 — Scan submission

Day 18 connects the Next.js new-scan route to the Ballerina public API. The
form now validates an authorized scan request in the browser, submits it once,
shows safe public API failures, and navigates accepted jobs to their detail
route.

## Submission flow

1. The user enters a hostname, IPv4 address, or IPv6 address.
2. Start and end ports must be whole numbers from `1` through `65535`, and the
   start port cannot exceed the end port.
3. The user must explicitly confirm ownership or permission to scan the target.
4. React Hook Form runs the shared Zod schema before making a request.
5. `scansApi.create` posts the public request to `POST /api/v1/scans` at the
   configured `NEXT_PUBLIC_API_BASE_URL`.
6. A successful response navigates to `/scans/{id}` using the Ballerina-owned
   public scan ID.

The form disables all controls while the request is pending, preventing
duplicate submissions. Client validation errors are associated with their
inputs through `aria-describedby` and `aria-invalid`. The first invalid field
receives focus through React Hook Form's normal validation behavior.

## Error handling

The frontend displays Ballerina's stable public error message in an alert. When
the response contains a request ID, the same ID is shown so a user can provide
it for log correlation. Internal URLs, request bodies, headers, and downstream
scanner diagnostics are not exposed.

Malformed or non-JSON API responses and network failures receive a generic,
actionable message. Editing any form value clears the previous server error so
stale feedback is not presented with a changed request.

Client validation improves feedback but is not a security boundary. Ballerina
and the Go scanner remain authoritative for allowlisting, DNS revalidation,
private-range blocking, port policy, capacity, and authorization enforcement.

## Local verification

Configure and start the backend services, then run the frontend:

```bash
cd frontend
cp .env.example .env.local
npm install
npm run dev
```

Open `http://localhost:3000/scans/new`. Submit an allowlisted target with a
valid port range and authorization checked. The browser should issue one
`POST /api/v1/scans` request and navigate to `/scans/{returned-id}` after a
`202 Accepted` response.

Verify these failure cases before integration sign-off:

- malformed or empty target;
- port outside `1`–`65535`;
- start port greater than end port;
- missing authorization confirmation;
- Ballerina validation or policy rejection;
- unavailable API or invalid API response.

## Automated checks

```bash
cd frontend
npm test
npm run typecheck
npm run lint
NEXT_PUBLIC_API_BASE_URL=http://localhost:9090 npm run build
```

The tests cover hostname/IP syntax, normalized requests, port boundaries and
ordering, mandatory authorization, prevention of invalid submission, successful
API submission and redirect, and public server-error/request-ID rendering.
