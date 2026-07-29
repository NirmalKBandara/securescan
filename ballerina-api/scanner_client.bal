import ballerina/http;

configurable string scannerServiceUrl = "http://localhost:8081";
configurable decimal scannerConnectTimeout = 2.0;
configurable decimal scannerResponseTimeout = 5.0;

final http:Client scannerClient = check new (scannerServiceUrl, {
    timeout: scannerResponseTimeout,
    socketConfig: {
        connectTimeOut: scannerConnectTimeout
    }
});

type ScannerCreateRequest record {|
    string target;
    int startPort;
    int endPort;
|};

type ScannerCreateResponse record {|
    string id;
    string status;
    string target;
    int startPort;
    int endPort;
|};

type ScannerPortResult record {|
    int port;
    string state;
    string? 'error = ();
|};

type ScannerResult record {|
    string target;
    int startPort;
    int endPort;
    ScannerPortResult[] results;
    int duration;
|};

type ScannerStatusResponse record {|
    string id;
    string status;
    string target;
    int startPort;
    int endPort;
    string createdAt;
    string updatedAt;
    ScannerResult? result = ();
    string? 'error = ();
|};

type ScannerFailure record {|
    string code;
|};

function createScannerJob(CreateScanRequest request, string requestId)
        returns ScannerCreateResponse|ScannerFailure {
    ScannerCreateRequest scannerRequest = {
        target: request.target.trim(),
        startPort: request.startPort,
        endPort: request.endPort
    };
    map<string|string[]> headers = {"X-Request-ID": requestId};

    http:Response|http:ClientError result =
        scannerClient->/internal/scans.post(scannerRequest, headers = headers);
    if result is http:ClientError {
        return {code: SCANNER_UNAVAILABLE};
    }

    if result.statusCode == http:STATUS_BAD_REQUEST {
        return classifyScannerBadRequest(result);
    }
    if result.statusCode == http:STATUS_BAD_GATEWAY ||
            result.statusCode == http:STATUS_SERVICE_UNAVAILABLE ||
            result.statusCode == http:STATUS_GATEWAY_TIMEOUT {
        return {code: SCANNER_UNAVAILABLE};
    }
    if result.statusCode != http:STATUS_ACCEPTED {
        return {code: INTERNAL_ERROR};
    }

    json|http:ClientError payload = result.getJsonPayload();
    if payload is http:ClientError {
        return {code: INTERNAL_ERROR};
    }
    ScannerCreateResponse|error response = payload.cloneWithType();
    if response is error {
        return {code: INTERNAL_ERROR};
    }
    return response;
}

function getScannerJob(string scanId, string requestId)
        returns ScannerStatusResponse|ScannerFailure {
    map<string|string[]> headers = {"X-Request-ID": requestId};
    http:Response|http:ClientError result =
        scannerClient->/internal/scans/[scanId].get(headers = headers);
    if result is http:ClientError {
        return {code: SCANNER_UNAVAILABLE};
    }

    if result.statusCode == http:STATUS_NOT_FOUND {
        return {code: SCAN_NOT_FOUND};
    }
    if result.statusCode == http:STATUS_BAD_GATEWAY ||
            result.statusCode == http:STATUS_SERVICE_UNAVAILABLE ||
            result.statusCode == http:STATUS_GATEWAY_TIMEOUT {
        return {code: SCANNER_UNAVAILABLE};
    }
    if result.statusCode != http:STATUS_OK {
        return {code: INTERNAL_ERROR};
    }

    json|http:ClientError payload = result.getJsonPayload();
    if payload is http:ClientError {
        return {code: INTERNAL_ERROR};
    }
    ScannerStatusResponse|error response = payload.cloneWithType();
    if response is error {
        return {code: INTERNAL_ERROR};
    }
    return response;
}

function classifyScannerBadRequest(http:Response response) returns ScannerFailure {
    json|http:ClientError payload = response.getJsonPayload();
    if payload is http:ClientError {
        return {code: INTERNAL_ERROR};
    }
    string prose = payload.toJsonString().toLowerAscii();
    if prose.includes("blocked") || prose.includes("allowlist") ||
            prose.includes("private") {
        return {code: BLOCKED_TARGET};
    }
    if prose.includes("port") {
        return {code: INVALID_PORT_RANGE};
    }
    if prose.includes("target") || prose.includes("host") {
        return {code: INVALID_TARGET};
    }
    return {code: INTERNAL_ERROR};
}
