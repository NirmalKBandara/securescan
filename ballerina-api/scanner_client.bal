import ballerina/http;

// Base URL is configurable
configurable string scannerServiceUrl = "http://localhost:8081";

final http:Client scannerClient = check new (scannerServiceUrl);

// Internal Go request
type ScannerCreateRequest record {|
    string target;
    int startPort;
    int endPort;
|};

// Response POST /internal/scans.
type ScannerCreateResponse record {|
    string id;
    string status;
    string target;
    int startPort;
    int endPort;
|};

function createScannerJob(CreateScanRequest request)
        returns ScannerCreateResponse|error {

    ScannerCreateRequest scannerRequest = {
        target: request.target.trim(),
        startPort: request.startPort,
        endPort: request.endPort
    };

    // Keep the HTTP response so its status can be checked before binding JSON.
    http:Response|http:ClientError result =
        scannerClient->/internal/scans.post(scannerRequest);

    if result is http:ClientError {
        return error("scanner request failed");
    }

    if result.statusCode != http:STATUS_ACCEPTED {
        return error("scanner returned an unexpected status");
    }

    json|http:ClientError payload = result.getJsonPayload();
    if payload is http:ClientError {
        return error("scanner returned invalid JSON");
    }

    ScannerCreateResponse|error response = payload.cloneWithType();
    if response is error {
        return error("scanner returned an unexpected response");
    }

    return response;
}
