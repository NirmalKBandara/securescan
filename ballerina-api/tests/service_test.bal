import ballerina/http;
import ballerina/test;

final http:Client healthClient = check new ("http://localhost:9091");

type MockScannerRequest record {|
    string target;
    int startPort;
    int endPort;
|};

type MockScannerAccepted record {|
    *http:Accepted;
    ScannerCreateResponse body;
|};

// This fake makes bal test independent from the real Go process.
service / on new http:Listener(18081) {
    resource function post internal/scans(
            @http:Payload MockScannerRequest request)
            returns MockScannerAccepted {

        return {
            body: {
                id: "00000000-0000-4000-8000-000000000007",
                status: "accepted",
                target: request.target,
                startPort: request.startPort,
                endPort: request.endPort
            }
        };
    }
}

@test:Config {}
function testHealthEndpoint() returns error? {
    http:Response response = check healthClient->/health;

    test:assertEquals(
            response.statusCode,
            http:STATUS_OK,
            msg = "GET /health must return HTTP 200"
    );

    json actualPayload = check response.getJsonPayload();

    json expectedPayload = {
        "success": true,
        "data": {
            "status": "ok",
            "serviceName": "securescan-api-test"
        }
    };

    test:assertEquals(
            actualPayload,
            expectedPayload,
            msg = "GET /health returned an unexpected JSON response"
    );
}

@test:Config {}
function testCreateScanAcceptsValidRequest() returns error? {
    json requestBody = {
        target: "scanme.nmap.org",
        startPort: 1,
        endPort: 100,
        authorized: true
    };

    http:Response response = check healthClient->/api/v1/scans.post(requestBody);

    test:assertEquals(
            response.statusCode,
            http:STATUS_ACCEPTED,
            msg = "Valid scan request must return HTTP 202"
    );

    json actualPayload = check response.getJsonPayload();

    json expectedPayload = {
        "success": true,
        "data": {
            "id": "00000000-0000-4000-8000-000000000007",
            "status": "accepted",
            "target": "scanme.nmap.org",
            "startPort": 1,
            "endPort": 100
        }
    };

    test:assertEquals(actualPayload, expectedPayload);
}

@test:Config {}
function testCreateScanRejectsEmptyTarget() returns error? {
    json requestBody = {
        target: "",
        startPort: 1,
        endPort: 100,
        authorized: true
    };

    http:Response response = check healthClient->/api/v1/scans.post(requestBody);

    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);

    json actualPayload = check response.getJsonPayload();

    test:assertEquals(actualPayload.success, false);
    test:assertEquals(actualPayload.'error.code, "INVALID_TARGET");
}

@test:Config {}
function testCreateScanRejectsInvalidPortRange() returns error? {
    json requestBody = {
        target: "scanme.nmap.org",
        startPort: 100,
        endPort: 1,
        authorized: true
    };

    http:Response response = check healthClient->/api/v1/scans.post(requestBody);

    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);

    json actualPayload = check response.getJsonPayload();

    test:assertEquals(actualPayload.success, false);
    test:assertEquals(actualPayload.'error.code, "INVALID_PORT_RANGE");
}

@test:Config {}
function testCreateScanRequiresAuthorizationConfirmation() returns error? {
    json requestBody = {
        target: "scanme.nmap.org",
        startPort: 1,
        endPort: 100,
        authorized: false
    };

    http:Response response = check healthClient->/api/v1/scans.post(requestBody);

    test:assertEquals(response.statusCode, http:STATUS_BAD_REQUEST);

    json actualPayload = check response.getJsonPayload();

    test:assertEquals(actualPayload.success, false);
    test:assertEquals(actualPayload.'error.code, "BLOCKED_TARGET");
}
