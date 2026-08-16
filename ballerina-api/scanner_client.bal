import ballerina/http;
import ballerina/uuid;

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
    string[] authorizedAddresses;
    int startPort;
    int endPort;
|};

type ScannerCreateResponse record {|
    string id;
    ScanJobStatus status;
    string target;
    int startPort;
    int endPort;
|};

type ScannerPortResult record {|
    string address;
    int port;
    ScanPortState state;
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
    ScanJobStatus status;
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

type ScannerErrorResponse record {|
    string code;
    string 'error;
|};

function createScannerJob(CreateScanRequest request, string[] authorizedAddresses,
        string requestId, string idempotencyKey)
        returns ScannerCreateResponse|ScannerFailure {
    ScannerCreateRequest scannerRequest = {
        target: request.target.trim(),
        authorizedAddresses: authorizedAddresses,
        startPort: request.startPort,
        endPort: request.endPort
    };
    map<string|string[]> headers = {
        "X-Request-ID": requestId,
        "X-Idempotency-Key": idempotencyKey
    };

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
    if result.statusCode == http:STATUS_TOO_MANY_REQUESTS {
        return {code: JOB_LIMIT_REACHED};
    }
    if result.statusCode != http:STATUS_ACCEPTED {
        return {code: INTERNAL_ERROR};
    }

    json|http:ClientError payload = result.getJsonPayload();
    if payload is http:ClientError {
        return {code: INTERNAL_ERROR};
    }
    ScannerCreateResponse|error response = payload.cloneWithType();
    if response is error || response.status != "accepted" ||
            !uuid:validate(response.id) ||
            response.target != scannerRequest.target ||
            response.startPort != scannerRequest.startPort ||
            response.endPort != scannerRequest.endPort {
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
    if response is error || response.id != scanId ||
            !uuid:validate(response.id) || !hasValidLifecycleShape(response) {
        return {code: INTERNAL_ERROR};
    }
    return response;
}

function classifyScannerBadRequest(http:Response response) returns ScannerFailure {
    json|http:ClientError payload = response.getJsonPayload();
    if payload is http:ClientError {
        return {code: INTERNAL_ERROR};
    }
    ScannerErrorResponse|error scannerError = payload.cloneWithType();
    if scannerError is error {
        return {code: INTERNAL_ERROR};
    }
    if scannerError.code == BLOCKED_TARGET {
        return {code: BLOCKED_TARGET};
    }
    if scannerError.code == INVALID_PORT_RANGE {
        return {code: INVALID_PORT_RANGE};
    }
    if scannerError.code == INVALID_TARGET {
        return {code: INVALID_TARGET};
    }
    return {code: INTERNAL_ERROR};
}

function hasValidLifecycleShape(ScannerStatusResponse response) returns boolean {
    if response.status == "completed" {
        return response.result is ScannerResult && response.'error is ();
    }
    if response.status == "failed" {
        return response.result is ();
    }
    return response.result is () && response.'error is ();
}
