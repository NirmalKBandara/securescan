import ballerina/http;
import ballerina/log;
import ballerina/uuid;

configurable int listenerPort = 9090;
configurable string serviceName = "securescan-api";

service / on new http:Listener(listenerPort) {
    resource function get health() returns HealthOk {
        HealthData healthData = {status: "ok", serviceName: serviceName};
        return {body: {success: true, data: healthData}};
    }

    resource function post api/v1/scans(@http:Payload CreateScanRequest request)
            returns CreateScanAccepted|BadRequestError|ServiceUnavailableError|
            InternalServerErrorResponse {
        string requestId = uuid:createType4AsString();
        log:printInfo("Scan create request received",
                requestId = requestId, operation = "createScan");

        BadRequestError? validationError = validateCreateScanRequest(request, requestId);
        if validationError is BadRequestError {
            return validationError;
        }

        ScannerCreateResponse|ScannerFailure scannerResult =
            createScannerJob(request, requestId);
        if scannerResult is ScannerFailure {
            log:printWarn("Scanner create request failed",
                    requestId = requestId, failureCode = scannerResult.code);
            return mapCreateFailure(scannerResult, requestId);
        }

        CreateScanData scanData = {
            id: scannerResult.id,
            status: scannerResult.status,
            target: scannerResult.target,
            startPort: scannerResult.startPort,
            endPort: scannerResult.endPort
        };
        log:printInfo("Scanner job created",
                requestId = requestId, operation = "createScan");
        return {
            headers: {requestId: requestId},
            body: {success: true, data: scanData}
        };
    }

    resource function get api/v1/scans/[string scanId]()
            returns ScanStatusOk|BadRequestError|NotFoundError|
            ServiceUnavailableError|InternalServerErrorResponse {
        string requestId = uuid:createType4AsString();
        log:printInfo("Scan status request received",
                requestId = requestId, operation = "getScanStatus");

        if !uuid:validate(scanId) {
            return badRequest(INVALID_SCAN_ID, "Scan ID must be a valid UUID",
                    {"field": "scanId"}, requestId);
        }

        ScannerStatusResponse|ScannerFailure scannerResult =
            getScannerJob(scanId, requestId);
        if scannerResult is ScannerFailure {
            log:printWarn("Scanner status request failed",
                    requestId = requestId, scanId = scanId,
                    failureCode = scannerResult.code);
            return mapScannerFailure(scannerResult, requestId);
        }

        ScanResultData? publicResult = ();
        ScannerResult? possibleResult = scannerResult.result;
        if possibleResult is ScannerResult {
            ScannerResult internalResult = possibleResult;
            ScanPortResult[] ports = from ScannerPortResult port in internalResult.results
                select {port: port.port, state: port.state};
            publicResult = {
                target: internalResult.target,
                startPort: internalResult.startPort,
                endPort: internalResult.endPort,
                results: ports,
                durationNanos: internalResult.duration
            };
        }
        ScanStatusData statusData = {
            id: scannerResult.id,
            status: scannerResult.status,
            target: scannerResult.target,
            startPort: scannerResult.startPort,
            endPort: scannerResult.endPort,
            createdAt: scannerResult.createdAt,
            updatedAt: scannerResult.updatedAt,
            result: publicResult
        };
        log:printInfo("Scan status returned",
                requestId = requestId, operation = "getScanStatus");
        return {
            headers: {requestId: requestId},
            body: {success: true, data: statusData}
        };
    }
}

function validateCreateScanRequest(CreateScanRequest request, string requestId)
        returns BadRequestError? {
    string trimmedTarget = request.target.trim();
    if trimmedTarget == "" {
        return badRequest(INVALID_TARGET, "Target is required",
                {"field": "target"}, requestId);
    }
    if request.startPort < 1 || request.startPort > 65535 {
        return badRequest(INVALID_PORT_RANGE,
                "Start port must be between 1 and 65535",
                {"field": "startPort", min: 1, max: 65535}, requestId);
    }
    if request.endPort < 1 || request.endPort > 65535 {
        return badRequest(INVALID_PORT_RANGE,
                "End port must be between 1 and 65535",
                {"field": "endPort", min: 1, max: 65535}, requestId);
    }
    if request.startPort > request.endPort {
        return badRequest(INVALID_PORT_RANGE,
                "Start port must be less than or equal to end port",
                {startPort: request.startPort, endPort: request.endPort}, requestId);
    }
    if !request.authorized {
        return badRequest(BLOCKED_TARGET,
                "Authorized-use confirmation is required before creating a scan",
                {"field": "authorized"}, requestId);
    }
    return ();
}

function mapCreateFailure(ScannerFailure failure, string requestId)
        returns BadRequestError|ServiceUnavailableError|
        InternalServerErrorResponse {
    if failure.code == BLOCKED_TARGET {
        return badRequest(BLOCKED_TARGET, "The target is not permitted", {},
                                                                         requestId);
    }
    if failure.code == INVALID_PORT_RANGE {
        return badRequest(INVALID_PORT_RANGE, "The port range is not permitted",
                {}, requestId);
    }
    if failure.code == INVALID_TARGET {
        return badRequest(INVALID_TARGET, "The target is invalid", {}, requestId);
    }
    if failure.code == SCANNER_UNAVAILABLE {
        ServiceUnavailableError unavailable = {
            headers: {requestId: requestId},
            body: {
                success: false,
                'error: {
                    code: SCANNER_UNAVAILABLE,
                    message: "Scanner service is temporarily unavailable",
                    requestId: requestId
                }
            }
        };
        return unavailable;
    }
    InternalServerErrorResponse internalError = {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: INTERNAL_ERROR,
                message: "Unable to process the scan request",
                requestId: requestId
            }
        }
    };
    return internalError;
}

function mapScannerFailure(ScannerFailure failure, string requestId)
        returns BadRequestError|NotFoundError|ServiceUnavailableError|
        InternalServerErrorResponse {
    if failure.code == BLOCKED_TARGET {
        return badRequest(BLOCKED_TARGET, "The target is not permitted", {},
                                                                         requestId);
    }
    if failure.code == INVALID_PORT_RANGE {
        return badRequest(INVALID_PORT_RANGE, "The port range is not permitted",
                {}, requestId);
    }
    if failure.code == INVALID_TARGET {
        return badRequest(INVALID_TARGET, "The target is invalid", {}, requestId);
    }
    if failure.code == SCAN_NOT_FOUND {
        NotFoundError notFound = {
            headers: {requestId: requestId},
            body: {
                success: false,
                'error: {
                    code: SCAN_NOT_FOUND,
                    message: "Scan not found",
                    requestId: requestId
                }
            }
        };
        return notFound;
    }
    if failure.code == SCANNER_UNAVAILABLE {
        ServiceUnavailableError unavailable = {
            headers: {requestId: requestId},
            body: {
                success: false,
                'error: {
                    code: SCANNER_UNAVAILABLE,
                    message: "Scanner service is temporarily unavailable",
                    requestId: requestId
                }
            }
        };
        return unavailable;
    }
    InternalServerErrorResponse internalError = {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: INTERNAL_ERROR,
                message: "Unable to process the scan request",
                requestId: requestId
            }
        }
    };
    return internalError;
}

function badRequest(string code, string message, map<json> details,
        string requestId) returns BadRequestError {
    return {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: code,
                message: message,
                requestId: requestId,
                details: details
            }
        }
    };
}
