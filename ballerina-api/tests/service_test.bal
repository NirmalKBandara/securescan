import ballerina/http;
import ballerina/test;

final http:Client apiClient = check new ("http://localhost:9091");

// Different deterministic UUIDs let the mock scanner represent each job state.
const string COMPLETED_SCAN_ID = "00000000-0000-4000-8000-000000000007";
const string RUNNING_SCAN_ID = "00000000-0000-4000-8000-000000000008";
const string FAILED_SCAN_ID = "00000000-0000-4000-8000-000000000009";
const string INVALID_STATUS_SCAN_ID = "00000000-0000-4000-8000-000000000010";
const string UNAVAILABLE_SCAN_ID = "00000000-0000-4000-8000-000000000011";
const string UNKNOWN_SCAN_ID = "00000000-0000-4000-8000-000000000099";

type MockScannerRequest record {|
    string target;
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

// The deterministic scanner fake also requires the correlation header, proving
// that the API propagates its generated request ID downstream.
service / on new http:Listener(18081) {
    resource function post internal/scans(
            @http:Payload MockScannerRequest request,
            @http:Header {name: "X-Request-ID"} string requestId)
            returns MockAccepted|MockAcceptedJson|MockBadRequest|MockUnavailable {
        if requestId == "" {
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
        // A running scan has timestamps but does not have a result yet.
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
        // Failed-job diagnostics stay inside the scanner boundary. The public
        // API must expose only the safe lifecycle status.
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
    // A running job must not manufacture a completed scan result.
    test:assertFalse(payload.toJsonString().includes("durationNanos"));
}

@test:Config {}
function testGetFailedScanDoesNotLeakInternalError() returns error? {
    http:Response response = check apiClient->/api/v1/scans/[FAILED_SCAN_ID];
    test:assertEquals(response.statusCode, http:STATUS_OK);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.data.id, FAILED_SCAN_ID);
    test:assertEquals(payload.data.status, "failed");
    // Scanner diagnostics belong in internal logs, not public responses.
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

// All integration failures must preserve the stable public envelope and
// correlation ID without returning the scanner's diagnostic text.
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
