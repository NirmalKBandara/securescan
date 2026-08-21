# SecureScan documentation

This index separates maintained operating and contract documents from the
day-by-day checkpoint record. Start with the path that matches your task.

## Reading paths

### Evaluate the system

1. [Project overview](../README.md)
2. [Architecture and trust boundaries](architecture/architecture-v1.md)
3. [Threat model](security/threat-model.md)
4. [Authorized-use policy](security/authorized-use-policy.md)
5. [Day 39 documentation checkpoint](project/day-39-documentation.md)
6. [Current architecture and flow diagrams](architecture/flows.md)
7. [Day 40 OpenAPI checkpoint](project/day-40-openapi-documentation.md)

### Run the local platform

1. [Configuration and secrets](deployment/day-36-configuration-secrets.md)
2. [WSO2 certificate prerequisite](../deployment/certs/README.md)
3. [Local six-service deployment](../deployment/README.md)
4. [Identity application registration](identity/day-22-wso2-oidc-client.md)
5. [API publication](gateway/day-27-api-manager-publishing.md)
6. [Gateway application and routing](gateway/day-28-gateway-routing.md)
7. [Target policy administration](security/day-30-allowed-target-administration.md)
8. [Security acceptance gate](security/day-33-security-checkpoint.md)
9. [Recovery and persistence gate](deployment/day-37-compose-recovery.md)

### Develop or review a component

- [Frontend guide](../frontend/README.md)
- [Ballerina API guide](../ballerina-api/README.md)
- [Go scanner guide](../scanner-engine/README.md)
- [Database guide](../database/README.md)
- [Deployment guide](../deployment/README.md)
- [Automated test gate](testing/day-38-automated-tests.md)

### Integrate with an API

- [Public Ballerina API](api/ballerina-public-api.md)
- [Internal scanner service API](api/scanner-service-api.md)
- [API Manager OpenAPI contract](../deployment/apim/securescan-api/Definitions/swagger.yaml)
- [Database schema and migration design](database/schema-design.md)

## Maintained reference

| Area | Documents |
| --- | --- |
| Architecture | [Version 1 architecture](architecture/architecture-v1.md) |
| Architecture diagrams | [System, login, and deployment flows](architecture/flows.md) |
| API | [Public API](api/ballerina-public-api.md), [scanner API](api/scanner-service-api.md) |
| Database | [Schema design](database/schema-design.md), [development commands](../database/README.md) |
| Security | [Threat model](security/threat-model.md), [target validation](security/target-validation.md), [authorized use](security/authorized-use-policy.md) |
| Operations | [Compose guide](../deployment/README.md), [configuration](deployment/day-36-configuration-secrets.md), [recovery](deployment/day-37-compose-recovery.md) |
| Testing | [Automated tests](testing/day-38-automated-tests.md), [security gate](security/day-33-security-checkpoint.md) |

## Checkpoint record

Checkpoint pages explain what changed, the acceptance criteria used at that
time, and any evidence that still requires a suitable runtime.

- Frontend: [Day 16](frontend/day-16-foundation.md), [Day 17](frontend/day-17-reusable-ui.md), [Day 18](frontend/day-18-scan-submission.md), [Day 19](frontend/day-19-scan-details-polling.md), [Day 20](frontend/day-20-history-checkpoint.md), [Day 32](frontend/day-32-administrator-dashboard.md)
- Identity: [Day 21](identity/day-21-wso2-identity-server.md), [Day 22](identity/day-22-wso2-oidc-client.md), [Day 23](identity/day-23-oidc-login.md), [Day 24](identity/day-24-route-authorization.md), [Day 25](identity/day-25-ownership-rbac.md)
- Gateway: [Day 26](gateway/day-26-wso2-api-manager.md), [Day 27](gateway/day-27-api-manager-publishing.md), [Day 28](gateway/day-28-gateway-routing.md), [Day 29](gateway/day-29-api-throttling.md)
- Security: [Day 30](security/day-30-allowed-target-administration.md), [Day 31](security/day-31-target-authorization.md), [Day 33](security/day-33-security-checkpoint.md)
- Deployment: [Day 34](deployment/day-34-application-dockerfiles.md), [Day 35](deployment/day-35-full-compose-topology.md), [Day 36](deployment/day-36-configuration-secrets.md), [Day 37](deployment/day-37-compose-recovery.md)
- Quality: [Day 38](testing/day-38-automated-tests.md), [Day 39](project/day-39-documentation.md), [Day 40](project/day-40-openapi-documentation.md)

## Documentation rules

- Describe the implemented repository state separately from live deployment
  evidence. Never report an unavailable runtime check as passing.
- Keep public, internal, and operator-only interfaces clearly separated.
- Link to the authoritative contract instead of duplicating long schemas or
  setup procedures.
- Use repository-relative links. `./scripts/verify.sh repository` rejects broken
  local Markdown targets, shell syntax errors, credential patterns, and
  whitespace errors.
