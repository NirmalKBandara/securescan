# Day 39 — Project documentation checkpoint

Day 39 turns the accumulated checkpoint notes into a maintained entry point for
users, operators, developers, API consumers, and security reviewers. It also
reconciles documents that still described early persistence or pre-auth phases
after the identity, Gateway, administration, deployment, and test work had been
implemented.

## Completed content

| Audience | Maintained starting point |
| --- | --- |
| Evaluator | [Project README](../../README.md) and [architecture](../architecture/architecture-v1.md) |
| Local operator | [Deployment guide](../../deployment/README.md), [configuration](../deployment/day-36-configuration-secrets.md), and [recovery gate](../deployment/day-37-compose-recovery.md) |
| Contributor | [Documentation index](../README.md), component guides, and [automated tests](../testing/day-38-automated-tests.md) |
| API consumer | [Public API](../api/ballerina-public-api.md) and [OpenAPI contract](../../deployment/apim/securescan-api/Definitions/swagger.yaml) |
| Security reviewer | [Threat model](../security/threat-model.md), [authorized-use policy](../security/authorized-use-policy.md), and [security checkpoint](../security/day-33-security-checkpoint.md) |

The project README now presents the current architecture, prerequisites,
component map, verification commands, safe local setup order, security
properties, asynchronous lifecycle, final roadmap state, and the remaining live
deployment gate. The architecture and API documents now describe the deployed
trust chain rather than future WSO2 integration.

The review also reconciled the shared frontend's `securescan:admin` scope,
current V001–V006 database design, encrypted-cookie token boundary, and the
two-stage WSO2 bootstrap. Certificate generation and WSO2 keystore/public-URL
wiring remain explicit operator-owned prerequisites; the repository provides
the frontend CA mount but does not claim to automate the WSO2 side.

## Documentation integrity gate

`scripts/verify-docs.sh` scans workspace Markdown links that point to
local files or directories. It fails when a target is missing or resolves
outside the repository. The root repository check runs it automatically:

```sh
./scripts/verify.sh repository
```

External URLs and same-page anchors are deliberately outside this offline gate.
API behavior remains covered by component tests and the OpenAPI artifact;
stateful identity and Gateway behavior remains covered by the manual deployment
gate.

## Source-of-truth boundaries

- `README.md` is the concise project entry point, not a chronological changelog.
- `docs/README.md` owns navigation and reading paths.
- `docs/architecture/architecture-v1.md` owns the current component, trust,
  network, data, and failure model.
- `docs/api/` and the API Manager OpenAPI file own interface contracts.
- Component READMEs own component-specific configuration and commands.
- Day checkpoint pages preserve acceptance decisions and runtime evidence.

When implementation changes, update the authoritative document and any affected
entry-point summary in the same change.

## Verification status

The offline documentation-link gate, repository secret check, shell syntax
checks, and whitespace check pass in this workspace. The source-level Go and
frontend gates passed at Day 38; Ballerina socket tests and the PostgreSQL/
Compose gates require a less restricted or Docker-capable environment.

Day 39 does not convert pending runtime evidence into a pass. In particular,
WSO2 application state, subscription and scope behavior, browser login, an
authorized real scan, restart persistence, and dependency recovery still need
the Day 37 procedure on a Docker-capable host before deployment.
