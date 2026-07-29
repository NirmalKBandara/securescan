import ballerina/http;
import ballerina/test;

final http:Client apiClient = check new ("http://localhost:9091");

const string COMPLETED_SCAN_ID = "00000000-0000-4000-8000-000000000007";
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
            returns MockAccepted|MockBadRequest|MockUnavailable {
        if requestId == "" {
            MockBadRequest missingHeader = {
                body: {"error": "missing request ID"}
            };
            return missingHeader;
        }
        if request.target == "blocked.example" {
            MockBadRequest blocked = {
                body: {"error": "target resolves to a blocked address"}
            };
            return blocked;
        }
        if request.target == "unavailable.example" {
            MockUnavailable unavailable = {
                body: {"error": "scanner unavailable"}
            };
            return unavailable;
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
            returns MockStatusOk|MockNotFound {
        if requestId == "" || scanId == UNKNOWN_SCAN_ID {
            MockNotFound notFound = {body: {"error": "scan job not found"}};
            return notFound;
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
                        {port: 1, state: "closed", 'error: "connection refused"},
                        {port: 2, state: "open"}
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
function testCreateScanMapsDownstreamBlockedTarget() returns error? {
    http:Response response = check postScan("blocked.example", 1, 100, true);
    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.'error.code, BLOCKED_TARGET);
    test:assertFalse(payload.toJsonString().includes("blocked address"));
}

@test:Config {}
function testGetCompletedScanReturnsSafeResult() returns error? {
    http:Response response = check apiClient->/api/v1/scans/[COMPLETED_SCAN_ID];
    test:assertEquals(response.statusCode, http:STATUS_OK);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.data.result.durationNanos, 1500000);
    test:assertTrue(payload.toJsonString().includes("\"state\":\"open\""));
    test:assertFalse(payload.toJsonString().includes("connection refused"));
}

@test:Config {}
function testGetUnknownValidScanId() returns error? {
    http:Response response = check apiClient->/api/v1/scans/[UNKNOWN_SCAN_ID];
    test:assertEquals(response.statusCode, http:STATUS_NOT_FOUND);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.'error.code, SCAN_NOT_FOUND);
}

@test:Config {}
function testCreateScanMapsUnavailableScanner() returns error? {
    http:Response response = check postScan("unavailable.example", 1, 100, true);
    test:assertEquals(response.statusCode, http:STATUS_SERVICE_UNAVAILABLE);
    json payload = check response.getJsonPayload();
    test:assertEquals(payload.'error.code, SCANNER_UNAVAILABLE);
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
