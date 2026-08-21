# SecureScan architecture, login, and deployment diagrams

These diagrams complement the maintained
[architecture description](architecture-v1.md). They show security boundaries,
not a promise that the pending Docker/WSO2 evidence has already passed.

## System architecture

```mermaid
flowchart LR
    B[Browser] -->|OIDC + PKCE| IS[WSO2 Identity Server]
    B -->|HttpOnly session| N[Next.js]
    N -->|Bearer access token| A[WSO2 API Manager]
    A -->|trusted subject, roles, secret| BI[Ballerina API]
    BI -->|durable lifecycle + audit| P[(PostgreSQL)]
    BI -->|authorized address pins| G[Go scanner]
    G -->|bounded TCP connect| T[Authorized target]
```

API Manager is the public API policy boundary. Ballerina repeats identity,
role, ownership, input, target-policy, and job-limit enforcement. Go performs
the final DNS-set and address-safety check before network access.

## Login and API request flow

```mermaid
sequenceDiagram
    actor User
    participant Web as Next.js
    participant IS as WSO2 IS
    participant APIM as WSO2 API Manager
    participant API as Ballerina

    User->>Web: Open protected route
    Web->>IS: Authorization Code + PKCE request
    IS-->>Web: Authorization code
    Web->>IS: Code + verifier
    IS-->>Web: ID/access tokens
    Web-->>User: Encrypted HttpOnly session cookie
    User->>Web: Same-origin /backend request
    Web->>APIM: Bearer access token
    APIM->>APIM: Validate token, scope, subscription, quota
    APIM->>API: Normalized subject/roles + backend secret
    API->>API: Authenticate and authorize again
    API-->>Web: Stable JSON + X-Request-ID
```

The normal browser client requests `securescan:scan`. A separate privileged
browser client is selected only for the safe `/admin` login destination and
requests `securescan:scan` plus `securescan:admin`. The selected client is
bound into the encrypted OIDC transaction. API Manager and Ballerina still
require the administrator scope and exact administrator role independently.

## Compose deployment

```mermaid
flowchart TB
    subgraph Host[Developer host — loopback listeners only]
      Browser
    end
    subgraph Identity[identity network]
      IS[WSO2 Identity Server]
      APIM[WSO2 API Manager]
      Next[Next.js]
    end
    subgraph Gateway[gateway network]
      APIM
      Next
    end
    subgraph Integration[integration network — internal]
      APIM
      Bal[Ballerina]
    end
    subgraph Scanner[scanner network]
      Bal
      Go[Go scanner]
    end
    subgraph Data[data network — internal]
      Bal
      DB[(PostgreSQL)]
    end
    Browser --> Next
    Browser --> IS
    Browser --> APIM
```

PostgreSQL, Ballerina, and Go are not published on the host. Network isolation
reduces accidental reachability but does not replace application controls.
