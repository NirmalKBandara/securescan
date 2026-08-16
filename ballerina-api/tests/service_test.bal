import ballerina/http;
import ballerina/sql;
import ballerina/test;

final http:Client apiClient = check new ("http://localhost:9091");

// Different deterministic UUIDs
const string COMPLETED_SCAN_ID = "00000000-0000-4000-8000-000000000007";
const string RUNNING_SCAN_ID = "00000000-0000-4000-8000-000000000008";
const string FAILED_SCAN_ID = "00000000-0000-4000-8000-000000000009";
const string INVALID_STATUS_SCAN_ID = "00000000-0000-4000-8000-000000000010";
const string UNAVAILABLE_SCAN_ID = "00000000-0000-4000-8000-000000000011";
const string UNKNOWN_SCAN_ID = "00000000-0000-4000-8000-000000000099";

type MockScannerRequest record {|
    string target;
    string[] authorizedAddresses;
    int startPort;
    int endPort;
|};

type MockAccepted record {|
    *http:Accepted;
    ScannerCreateResponse body;
|};

type MockAcceptedJson record {|
    *http:Accepted;
    json body;
|};

type MockBadRequest record {|
    *http:BadRequest;
    json body;
|};

type MockUnavailable record {|
    *http:ServiceUnavailable;
    json body;
|};

type MockTooManyRequests record {|
    *http:TooManyRequests;
    json body;
|};

type MockStatusOk record {|
    *http:Ok;
    ScannerStatusResponse body;
|};

type MockStatusJsonOk record {|
    *http:Ok;
    json body;
|};

type MockNotFound record {|
    *http:NotFound;
    json body;
|};

// API propagates its generated request ID downstream.
service / on new http:Listener(18081) {
    resource function post internal/scans(
            @http:Payload MockScannerRequest request,
            @http:Header {name: "X-Request-ID"} string requestId,
            @http:Header {name: "X-Idempotency-Key"} string idempotencyKey)
            returns MockAccepted|MockAcceptedJson|MockBadRequest|MockUnavailable|
            MockTooManyRequests {
        if requestId == "" || idempotencyKey == "" {
            MockBadRequest missingHeader = {
                body: {
                    "code": "INVALID_REQUEST",
                    "error": "missing request ID"
                }
            };
            return missingHeader;
        }
        if request.target == "blocked.example" {
            MockBadRequest blocked = {
                body: {
                    "code": BLOCKED_TARGET,
                    "error": "target resolves to a blocked address"
                }
            };
            return blocked;
        }
        if request.target == "invalid-target.example" {
            MockBadRequest invalidTarget = {
                body: {
                    "code": INVALID_TARGET,
                    "error": "internal target validation diagnostic"
                }
            };
            return invalidTarget;
        }
        if request.target == "invalid-port-range.example" {
            MockBadRequest invalidPortRange = {
                body: {
                    "code": INVALID_PORT_RANGE,
                    "error": "internal port policy diagnostic"
                }
            };
            return invalidPortRange;
        }
        if request.target == "unknown-error.example" {
            MockBadRequest unknownError = {
                body: {
                    "code": "PRIVATE_SCANNER_ERROR",
                    "error": "internal scanner implementation detail"
                }
            };
            return unknownError;
        }
        if request.target == "unavailable.example" {
            MockUnavailable unavailable = {
                body: {"error": "scanner unavailable"}
            };
            return unavailable;
        }
        if request.target == "busy.example" {
            MockTooManyRequests busy = {
                body: {"code": JOB_LIMIT_REACHED, "error": "scanner capacity reached"}
            };
            return busy;
        }
        if request.target == "malformed-response.example" {
            MockAcceptedJson malformed = {
                body: {
                    "id": "not-a-complete-scanner-response",
                    "status": "accepted"
                }
            };
            return malformed;
        }
        MockAccepted accepted = {
            body: {
                id: COMPLETED_SCAN_ID,
                status: "accepted",
                target: request.target,
                startPort: request.startPort,
                endPort: request.endPort
            }
        };
        return accepted;
    }

    resource function get internal/scans/[string scanId](
            @http:Header {name: "X-Request-ID"} string requestId)
            returns MockStatusOk|MockStatusJsonOk|MockNotFound|MockUnavailable {
        if requestId == "" || scanId == UNKNOWN_SCAN_ID {
            MockNotFound notFound = {body: {"error": "scan job not found"}};
            return notFound;
        }
        if scanId == UNAVAILABLE_SCAN_ID {
            MockUnavailable unavailable = {
                body: {"error": "scanner unavailable"}
            };
            return unavailable;
        }
        if scanId == INVALID_STATUS_SCAN_ID {
            MockStatusJsonOk malformed = {
                body: {
                    "id": INVALID_STATUS_SCAN_ID,
                    "status": "dial tcp: internal scanner diagnostic",
                    "target": "scanme.nmap.org",
                    "startPort": 1,
                    "endPort": 2,
                    "createdAt": "2026-07-25T10:00:00Z",
                    "updatedAt": "2026-07-25T10:00:01Z"
                }
            };
            return malformed;
        }
        // A running scan has timestamps
        if scanId == RUNNING_SCAN_ID {
            MockStatusOk running = {
                body: {
                    id: RUNNING_SCAN_ID,
                    status: "running",
                    target: "scanme.nmap.org",
                    startPort: 1,
                    endPort: 2,
                    createdAt: "2026-07-25T10:00:00Z",
                    updatedAt: "2026-07-25T10:00:00Z"
                }
            };
            return running;
        }

        if scanId == FAILED_SCAN_ID {
            MockStatusOk failed = {
                body: {
                    id: FAILED_SCAN_ID,
                    status: "failed",
                    target: "scanme.nmap.org",
                    startPort: 1,
                    endPort: 2,
                    createdAt: "2026-07-25T10:00:00Z",
                    updatedAt: "2026-07-25T10:00:01Z",
                    'error: "dial tcp: internal scanner diagnostic"
                }
            };
            return failed;
        }
        MockStatusOk status = {
            body: {
                id: COMPLETED_SCAN_ID,
                status: "completed",
                target: "scanme.nmap.org",
                startPort: 1,
                endPort: 2,
                createdAt: "2026-07-25T10:00:00Z",
                updatedAt: "2026-07-25T10:00:01Z",
                result: {
                    target: "scanme.nmap.org",
                    startPort: 1,
                    endPort: 2,
                    results: [
                        {
                            address: "45.33.32.156",
                            port: 1,
                            state: "closed",
                            'error: "connection refused"
                        },
                        {address: "45.33.32.156", port: 2, state: "open"}
                    ],
                    duration: 1500000
                }
            }
        };
        return status;
    }
}

@test:Config {}
function testHealthEndpoint() returns error? {
    http:Response response = check apiClient->/health;
    test:assertEquals(response.statusCode, http:STATUS_OK);
    test:assertEquals(check response.getJsonPayload(), {
                                                           "success": true,
                                                           "data": {"status": "ok", "serviceName": "securescan-api-test"}
                                                       });
}

@test:Config {}
function testPersistedCompletedScanUsesPublicIdAndStoredResults() {
    PersistedScanJob job = {
        id: "00000000-0000-4000-8000-000000000012",
        ownerSubject: "alice",
        scannerScanId: COMPLETED_SCAN_ID,
        target: "scanme.nmap.org",
        startPort: 1,
        endPort: 2,
        status: "COMPLETED",
        durationNanos: 1500000,
        createdAt: "2026-08-03T00:00:00Z",
        updatedAt: "2026-08-03T00:00:01Z"
    };
    ScanStatusOk response = persistedScanResponse(job,
            [{address: "45.33.32.156", port: 2, state: "open"}], "request-id");
    test:assertEquals(response.body.data.id, job.id);
    test:assertEquals(response.body.data.status, "completed");
    test:assertEquals(response.body.data.result.durationNanos, 1500000);
}

@test:Config {}
function testPersistedRunningScanDoesNotExposeResult() {
    PersistedScanJob job = {
        id: "00000000-0000-4000-8000-000000000013",
        ownerSubject: "alice",
        scannerScanId: RUNNING_SCAN_ID,
        target: "scanme.nmap.org",
        startPort: 1,
        endPort: 2,
        status: "RUNNING",
        createdAt: "2026-08-03T00:00:00Z",
        updatedAt: "2026-08-03T00:00:01Z"
    };
    ScanStatusOk response = persistedScanResponse(job, [], "request-id");
    test:assertEquals(response.body.data.status, "running");
    test:assertEquals(response.body.data.result, ());
}

@test:Config {}
function testPersistedQueuedScanIsDistinctFromRunning() {
    PersistedScanJob job = {
        id: "00000000-0000-4000-8000-000000000014",
        ownerSubject: "alice",
        target: "scanme.nmap.org",
        startPort: 1,
        endPort: 2,
        status: "QUEUED",
        createdAt: "2026-08-05T00:00:00Z",
        updatedAt: "2026-08-05T00:00:00Z"
    };
    ScanStatusOk response = persistedScanResponse(job, [], "request-id");
    test:assertEquals(response.body.data.status, "queued");
    test:assertEquals(response.body.data.result, ());
}

@test:Config {}
function testPersistedBlockedScanExposesSafeFailureCode() {
    PersistedScanJob job = {
        id: "00000000-0000-4000-8000-000000000019",
        ownerSubject: "alice",
        target: "blocked.example",
        startPort: 1,
        endPort: 2,
        status: "BLOCKED",
        failureCode: BLOCKED_TARGET,
        createdAt: "2026-08-10T00:00:00Z",
        updatedAt: "2026-08-10T00:00:01Z"
    };
    ScanStatusOk response = persistedScanResponse(job, [], "request-id");
    test:assertEquals(response.body.data.status, "blocked");
    test:assertEquals(response.body.data.failureCode, BLOCKED_TARGET);
    test:assertEquals(response.body.data.result, ());
}

@test:Config {}
function testHistoryProjectionUsesStablePublicLifecycle() {
    PersistedScanHistoryItem stored = {
        id: "00000000-0000-4000-8000-000000000015",
        target: "scanme.nmap.org",
        startPort: 1,
        endPort: 2,
        status: "BLOCKED",
        createdAt: "2026-08-05T00:00:00Z",
        updatedAt: "2026-08-05T00:00:01Z"
    };
    ScanHistoryItem item = persistedHistoryItem(stored);
    test:assertEquals(item.id, stored.id);
    test:assertEquals(item.status, "blocked");
}

@test:Config {}
function testHistoryEndpointRejectsUnboundedPageSize() returns error? {
    http:Response response = check apiClient->/api/v1/scans.get(pageSize = 101);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.'error.code, INVALID_REQUEST);
}

@test:Config {}
function testLifecycleUpdateOutcomesExposeUnchangedRows() {
    sql:ExecutionResult applied = {
        affectedRowCount: 1,
        lastInsertId: ()
    };
    sql:ExecutionResult unchanged = {
        affectedRowCount: 0,
        lastInsertId: ()
    };
    sql:ExecutionResult unknown = {
        affectedRowCount: (),
        lastInsertId: ()
    };
    test:assertEquals(scanUpdateOutcome(applied), "APPLIED");
    test:assertEquals(scanUpdateOutcome(unchanged), "UNCHANGED");
    test:assertTrue(scanUpdateOutcome(unknown) is error);
    test:assertTrue(requireAppliedUpdate(unchanged, "stale update") is error);
}

@test:Config {}
function testDispatchLeaseMustOutlastScannerTimeout() {
    test:assertEquals(validateDispatchLease(6, 5.0), ());
    test:assertTrue(validateDispatchLease(5, 5.0) is error);
    test:assertTrue(validateDispatchLease(4, 5.0) is error);
}

@test:Config {}
function testAsyncConfigurationEnforcesOneActiveScanPerOwner() {
    test:assertEquals(validateAsyncConfiguration(1, 1), ());
    test:assertTrue(validateAsyncConfiguration(0, 1) is error);
    test:assertTrue(validateAsyncConfiguration(2, 1) is error);
    test:assertTrue(validateAsyncConfiguration(1, 0) is error);
}

@test:Config {}
function testSecurityLimitConfigurationCannotWeakenHardCaps() {
    test:assertEquals(validateSecurityLimits(1000, 4096), ());
    test:assertEquals(validateSecurityLimits(500, 2048), ());
    test:assertTrue(validateSecurityLimits(1001, 4096) is error);
    test:assertTrue(validateSecurityLimits(1000, 4097) is error);
}

@test:Config {}
function testGatewayIdentityRequiresSharedSecretAndApplicationRole() {
    AuthContext|UnauthorizedError|ForbiddenError user =
        authenticateGatewayIdentity("test-secret", "alice",
            "everyone, securescan-user", "test-secret", "request-id");
    test:assertTrue(user is AuthContext);
    if user is AuthContext {
        test:assertEquals(user.subject, "alice");
        test:assertFalse(user.admin);
    }

    AuthContext|UnauthorizedError|ForbiddenError admin =
        authenticateGatewayIdentity("test-secret", "admin-subject",
            "securescan-admin", "test-secret", "request-id");
    test:assertTrue(admin is AuthContext);
    if admin is AuthContext {
        test:assertTrue(admin.admin);
        test:assertTrue(canAccessOwner(admin, "alice"));
    }

    AuthContext|UnauthorizedError|ForbiddenError wrongSecret =
        authenticateGatewayIdentity("wrong", "alice", "securescan-user",
            "test-secret", "request-id");
    test:assertTrue(wrongSecret is UnauthorizedError);

    AuthContext|UnauthorizedError|ForbiddenError unrelatedRole =
        authenticateGatewayIdentity("test-secret", "alice", "administrator",
            "test-secret", "request-id");
    test:assertTrue(unrelatedRole is ForbiddenError);

    foreach string lookalike in ["Securescan-admin", "securescan-admin-extra",
            "prefix-securescan-admin", "administrator"] {
        AuthContext|UnauthorizedError|ForbiddenError escalated =
            authenticateGatewayIdentity("test-secret", "alice", lookalike,
                "test-secret", "request-id");
        test:assertTrue(escalated is ForbiddenError,
                msg = string `lookalike role '${lookalike}' must not grant access`);
    }
}

@test:Config {}
function testAuthenticationCannotBeDisabledOutsideIsolatedTests() {
    test:assertEquals(validateAuthenticationSettings(false, "",
            "securescan-api-test", "http://localhost:18081"), ());
    test:assertTrue(validateAuthenticationSettings(false, "",
            "securescan-api", "http://localhost:8081") is error);
    test:assertTrue(validateAuthenticationSettings(true, "too-short",
            "securescan-api", "http://localhost:8081") is error);
    test:assertEquals(validateAuthenticationSettings(true,
            "12345678901234567890123456789012", "securescan-api",
            "http://localhost:8081"), ());
}

@test:Config {}
function testAllowedTargetAdministrationRequiresAdminRole() {
    AuthContext user = {subject: "alice", admin: false};
    AuthContext admin = {subject: "admin", admin: true};
    test:assertTrue(requireAdmin(user, "request-id") is ForbiddenError);
    test:assertEquals(requireAdmin(admin, "request-id"), ());
}

@test:Config {}
function testAllowedTargetHostnameNormalizationAndValidation() {
    CreateAllowedTargetRequest request = {
        targetKind: "HOSTNAME",
        target: "  Scan.Dev.Example  ",
        startPort: 80,
        endPort: 443
    };
    string|BadRequestError normalized =
        validateAllowedTargetRequest(request, "request-id");
    test:assertEquals(normalized, "scan.dev.example");

    request.target = "wildcard.*.example";
    test:assertTrue(validateAllowedTargetRequest(request, "request-id")
            is BadRequestError);

    test:assertTrue(validExactHostname("scanme.nmap.org"));
    test:assertFalse(validExactHostname("bad_name.example"));
    test:assertFalse(validExactHostname("-bad.example"));
    test:assertFalse(validExactHostname("bad.example."));
}

@test:Config {}
function testAuthorizedPublicTargetPassesPolicy() {
    test:assertTrue(targetPassesAuthorization(
                    "10000000-0000-4000-8000-000000000001", ["45.33.32.156"]));
}

@test:Config {}
function testUnauthorizedAndDisabledHostnameRulesAreBlocked() {
    test:assertFalse(targetPassesAuthorization((), ["45.33.32.156"]));
}

@test:Config {}
function testPrivateAndUnsafeDnsAnswersAreBlocked() returns error? {
    test:assertFalse(addressIsSafe("127.0.0.1"));
    test:assertFalse(addressIsSafe("10.0.0.1"));
    test:assertFalse(addressIsSafe("169.254.169.254"));
    test:assertFalse(addressIsSafe("0.0.0.0"));
    test:assertFalse(addressIsSafe("224.0.0.1"));
    test:assertFalse(addressIsSafe("fd00:ec2::254"));
    test:assertFalse(addressIsSafe("::"));
    test:assertFalse(addressIsSafe("::1"));
    test:assertFalse(addressIsSafe("fe80::1"));
    test:assertFalse(addressIsSafe("ff02::1"));
    test:assertFalse(addressIsSafe("fc00::1"));
    test:assertFalse(targetPassesAuthorization(
                    "10000000-0000-4000-8000-000000000001",
                    ["45.33.32.156", "192.168.1.10"]));

    string[] localhostAnswers = check resolveAllAddresses("localhost");
    test:assertTrue(localhostAnswers.length() > 0);
    test:assertFalse(allAddressesSafe(localhostAnswers));
}

@test:Config {}
function testAllowedTargetKindAndPortShapeValidation() {
    CreateAllowedTargetRequest exactIp = {
        targetKind: "IP",
        target: "192.0.2.10/32"
    };
    test:assertTrue(validateAllowedTargetRequest(exactIp, "request-id")
            is BadRequestError);

    CreateAllowedTargetRequest cidr = {
        targetKind: "CIDR",
        target: "192.0.2.0"
    };
    test:assertTrue(validateAllowedTargetRequest(cidr, "request-id")
            is BadRequestError);

    CreateAllowedTargetRequest incompletePorts = {
        targetKind: "HOSTNAME",
        target: "scan.dev.example",
        startPort: 443
    };
    test:assertTrue(validateAllowedTargetRequest(incompletePorts, "request-id")
            is BadRequestError);
}

@test:Config {}
function testOrdinaryUserCannotSelectAnotherOwner() {
    AuthContext user = {subject: "alice", admin: false};
    test:assertTrue(canAccessOwner(user, "alice"));
    test:assertFalse(canAccessOwner(user, "bob"));
}

@test:Config {}
function testScannerResponseMustMatchPersistedJob() {
    PersistedScanJob job = {
        id: "00000000-0000-4000-8000-000000000016",
        ownerSubject: "alice",
        scannerScanId: RUNNING_SCAN_ID,
        target: "scanme.nmap.org",
        startPort: 1,
        endPort: 2,
        status: "RUNNING",
        createdAt: "2026-08-05T00:00:00Z",
        updatedAt: "2026-08-05T00:00:01Z"
    };
    ScannerStatusResponse matching = {
        id: RUNNING_SCAN_ID,
        status: "running",
        target: "scanme.nmap.org",
        startPort: 1,
        endPort: 2,
        createdAt: "2026-08-05T00:00:00Z",
        updatedAt: "2026-08-05T00:00:01Z"
    };
    test:assertTrue(scannerResponseMatchesJob(job, RUNNING_SCAN_ID, matching));

    ScannerStatusResponse wrongTarget = matching.clone();
    wrongTarget.target = "other.example";
    test:assertFalse(scannerResponseMatchesJob(job, RUNNING_SCAN_ID, wrongTarget));
}

@test:Config {}
function testHistoryPageSizeIsBounded() {
    test:assertEquals(validateHistoryLimit(1), ());
    test:assertEquals(validateHistoryLimit(100), ());
    test:assertTrue(validateHistoryLimit(0) is error);
    test:assertTrue(validateHistoryLimit(101) is error);
}

@test:Config {}
function testCreateScanAcceptsValidRequest() returns error? {
    http:Response response = check postScan("scanme.nmap.org", 1, 100, true);
    test:assertEquals(response.statusCode, http:STATUS_ACCEPTED);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.data.status, "accepted");
    test:assertEquals(payload.data.target, "scanme.nmap.org");
}

@test:Config {}
function testCreateScanRejectsLocalValidation() returns error? {
    http:Response response = check postScan("", 1, 100, true);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.'error.code, INVALID_TARGET);
}

@test:Config {}
function testCreateScanRejectsInvalidPortRange() returns error? {
    http:Response response = check postScan("scanme.nmap.org", 100, 1, true);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.'error.code, INVALID_PORT_RANGE);
}

@test:Config {}
function testCreateScanEnforcesOneThousandPortLimit() returns error? {
    http:Response allowed = check postScan("scanme.nmap.org", 1, 1000, true);
    test:assertEquals(allowed.statusCode, http:STATUS_ACCEPTED);
    http:Response rejected = check postScan("scanme.nmap.org", 1, 1001, true);
    test:assertEquals(rejected.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check rejected.getJsonPayload();
    test:assertEquals(payload.'error.code, INVALID_PORT_RANGE);
}

@test:Config {}
function testCreateScanParserRejectsOversizedBody() {
    string oversized = "";
    foreach int _ in 1 ... 4097 {
        oversized += "x";
    }
    CreateScanRequest|BadRequestError|PayloadTooLargeError parsed =
        parseCreateScanRequest(oversized.toBytes(), "request-id");
    test:assertTrue(parsed is PayloadTooLargeError);
    if parsed is PayloadTooLargeError {
        test:assertEquals(parsed.body.'error.code, REQUEST_TOO_LARGE);
    }
}

@test:Config {}
function testCreateScanRequiresAuthorizationAcknowledgement() returns error? {
    http:Response response = check postScan("scanme.nmap.org", 1, 2, false);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.'error.code, BLOCKED_TARGET);
}

@test:Config {}
function testCreateScanRejectsWrongRequestShapeWithRequestId() returns error? {
    json incompleteBody = {
        target: "scanme.nmap.org",
        authorized: true
    };
    http:Response response =
        check apiClient->/api/v1/scans.post(incompleteBody);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.'error.code, INVALID_REQUEST);
    test:assertEquals(
            payload.'error.requestId,
            check response.getHeader("X-Request-ID")
    );
}

@test:Config {}
function testCreateScanMapsDownstreamBlockedTarget() returns error? {
    http:Response response = check postScan("blocked.example", 1, 100, true);
    check assertSafeError(response, http:STATUS_BAD_REQUEST, BLOCKED_TARGET,
            "blocked address");
}

@test:Config {}
function testCreateScanMapsDownstreamInvalidTargetSafely() returns error? {
    http:Response response =
        check postScan("invalid-target.example", 1, 100, true);
    check assertSafeError(response, http:STATUS_BAD_REQUEST, INVALID_TARGET,
            "internal target validation diagnostic");
}

@test:Config {}
function testCreateScanMapsDownstreamInvalidPortRangeSafely() returns error? {
    http:Response response =
        check postScan("invalid-port-range.example", 1, 100, true);
    check assertSafeError(response, http:STATUS_BAD_REQUEST,
            INVALID_PORT_RANGE, "internal port policy diagnostic");
}

@test:Config {}
function testCreateScanMapsUnknownDownstreamErrorSafely() returns error? {
    http:Response response =
        check postScan("unknown-error.example", 1, 100, true);
    check assertSafeError(response, http:STATUS_INTERNAL_SERVER_ERROR,
            INTERNAL_ERROR, "internal scanner implementation detail");
}

@test:Config {}
function testGetCompletedScanReturnsSafeResult() returns error? {
    http:Response response = check apiClient->/api/v1/scans/[COMPLETED_SCAN_ID];
    test:assertEquals(response.statusCode, http:STATUS_OK);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.data.result.durationNanos, 1500000);
    test:assertTrue(
            payload.toJsonString().includes("\"address\":\"45.33.32.156\"")
    );
    test:assertTrue(payload.toJsonString().includes("\"state\":\"open\""));
    test:assertFalse(payload.toJsonString().includes("connection refused"));
}

@test:Config {}
function testGetRunningScanReturnsStatusWithoutResult() returns error? {
    http:Response response = check apiClient->/api/v1/scans/[RUNNING_SCAN_ID];
    test:assertEquals(response.statusCode, http:STATUS_OK);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.data.id, RUNNING_SCAN_ID);
    test:assertEquals(payload.data.status, "running");
    test:assertFalse(payload.toJsonString().includes("durationNanos"));
}

@test:Config {}
function testGetFailedScanDoesNotLeakInternalError() returns error? {
    http:Response response = check apiClient->/api/v1/scans/[FAILED_SCAN_ID];
    test:assertEquals(response.statusCode, http:STATUS_OK);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.data.id, FAILED_SCAN_ID);
    test:assertEquals(payload.data.status, "failed");
    test:assertFalse(
            payload.toJsonString().includes("internal scanner diagnostic")
    );
}

@test:Config {}
function testGetUnknownValidScanId() returns error? {
    http:Response response = check apiClient->/api/v1/scans/[UNKNOWN_SCAN_ID];
    check assertSafeError(response, http:STATUS_NOT_FOUND, SCAN_NOT_FOUND,
            "scan job not found");
}

@test:Config {}
function testCreateScanMapsUnavailableScanner() returns error? {
    http:Response response = check postScan("unavailable.example", 1, 100, true);
    check assertSafeError(response, http:STATUS_SERVICE_UNAVAILABLE,
            SCANNER_UNAVAILABLE, "scanner unavailable");
}

@test:Config {}
function testCreateScanMapsScannerCapacityLimit() returns error? {
    http:Response response = check postScan("busy.example", 1, 100, true);
    check assertSafeError(response, http:STATUS_TOO_MANY_REQUESTS,
            JOB_LIMIT_REACHED, "scanner capacity reached");
}

@test:Config {}
function testCreateScanMapsMalformedDownstreamResponse() returns error? {
    http:Response response =
        check postScan("malformed-response.example", 1, 2, true);
    check assertSafeError(response, http:STATUS_INTERNAL_SERVER_ERROR,
            INTERNAL_ERROR, "not-a-complete");
}

@test:Config {}
function testGetMapsUnavailableScanner() returns error? {
    http:Response response =
        check apiClient->/api/v1/scans/[UNAVAILABLE_SCAN_ID];
    check assertSafeError(response, http:STATUS_SERVICE_UNAVAILABLE,
            SCANNER_UNAVAILABLE, "scanner unavailable");
}

@test:Config {}
function testGetRejectsInvalidDownstreamStatusSafely() returns error? {
    http:Response response =
        check apiClient->/api/v1/scans/[INVALID_STATUS_SCAN_ID];
    check assertSafeError(response, http:STATUS_INTERNAL_SERVER_ERROR,
            INTERNAL_ERROR, "dial tcp");
}

@test:Config {}
function testGetRejectsMalformedScanIdLocally() returns error? {
    string malformedId = "not-a-uuid";
    http:Response response = check apiClient->/api/v1/scans/[malformedId];
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.'error.code, INVALID_SCAN_ID);
}

@test:Config {}
function testResponseIncludesRequestId() returns error? {
    http:Response response = check postScan("scanme.nmap.org", 1, 2, true);
    json payload = check response.getJsonPayload();
    string headerRequestId = check response.getHeader("X-Request-ID");
    test:assertTrue(headerRequestId.length() > 0);
    test:assertEquals(payload.data.id, COMPLETED_SCAN_ID);
}

@test:Config {}
function testGetResponseIncludesRequestId() returns error? {
    http:Response response = check apiClient->/api/v1/scans/[COMPLETED_SCAN_ID];
    string headerRequestId = check response.getHeader("X-Request-ID");
    test:assertTrue(headerRequestId.length() > 0);
}

@test:Config {}
function testErrorRequestIdMatchesHeader() returns error? {
    http:Response response = check postScan("", 1, 2, true);
    json payload = check response.getJsonPayload();
    string headerRequestId = check response.getHeader("X-Request-ID");
    test:assertEquals(payload.'error.requestId, headerRequestId);
}

function postScan(string target, int startPort, int endPort, boolean authorized)
        returns http:Response|error {
    json requestBody = {
        target: target,
        startPort: startPort,
        endPort: endPort,
        authorized: authorized
    };
    return apiClient->/api/v1/scans.post(requestBody);
}

function assertSafeError(http:Response response, int expectedStatus,
        string expectedCode, string forbiddenText) returns error? {
    test:assertEquals(response.statusCode, expectedStatus);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.success, false);
    test:assertEquals(payload.'error.code, expectedCode);
    string headerRequestId = check response.getHeader("X-Request-ID");
    test:assertTrue(headerRequestId.length() > 0);
    test:assertEquals(payload.'error.requestId, headerRequestId);
    test:assertFalse(payload.toJsonString().includes(forbiddenText));
}
