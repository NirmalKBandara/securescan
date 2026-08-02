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

    resource function post api/v1/scans(http:Request httpRequest)
            returns CreateScanAccepted|BadRequestError|ServiceUnavailableError|
            InternalServerErrorResponse {
        string requestId = uuid:createType4AsString();
        log:printInfo("Scan create request received",
                requestId = requestId, operation = "createScan");

        // Parse inside the resource so malformed or wrongly shaped requests
        // still receive the standard envelope and correlation ID.
        json|http:ClientError payload = httpRequest.getJsonPayload();
        if payload is http:ClientError {
            return badRequest(INVALID_REQUEST,
                    "Request body must contain valid JSON", {}, requestId);
        }
        CreateScanRequest|error boundRequest = payload.cloneWithType();
        if boundRequest is error {
            return badRequest(INVALID_REQUEST,
                    "Request body does not match the scan contract", {}, requestId);
        }
        CreateScanRequest request = boundRequest;

        BadRequestError? validationError = validateCreateScanRequest(request, requestId);
        if validationError is BadRequestError {
            return validationError;
        }

        string publicScanId = uuid:createType4AsString();
        if persistenceEnabled {
            error? insertError = insertQueuedScan(publicScanId, request);
            if insertError is error {
                log:printError("Unable to persist queued scan", insertError,
                        requestId = requestId, scanId = publicScanId);
                return persistenceUnavailable(requestId);
            }
        }

        ScannerCreateResponse|ScannerFailure scannerResult =
            createScannerJob(request, requestId);
        if scannerResult is ScannerFailure {
            if persistenceEnabled {
                error? updateError = markScanDispatchFailed(publicScanId,
                        scannerResult.code, scannerResult.code == BLOCKED_TARGET);
                if updateError is error {
                    log:printError("Unable to persist scan dispatch failure",
                            updateError, requestId = requestId,
                            scanId = publicScanId);
                }
            }
            log:printWarn("Scanner create request failed",
                    requestId = requestId, failureCode = scannerResult.code);
            return mapCreateFailure(scannerResult, requestId);
        }

        if persistenceEnabled {
            error? updateError = markScanDispatched(publicScanId, scannerResult.id);
            if updateError is error {
                log:printError("Unable to persist scanner correlation", updateError,
                        requestId = requestId, scanId = publicScanId);
                return persistenceUnavailable(requestId);
            }
        }

        CreateScanData scanData = {
            id: persistenceEnabled ? publicScanId : scannerResult.id,
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

        if persistenceEnabled {
            return getPersistedScanStatus(scanId, requestId);
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
                select {
                    address: port.address,
                    port: port.port,
                    state: port.state
                };
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

function getPersistedScanStatus(string scanId, string requestId)
        returns ScanStatusOk|NotFoundError|ServiceUnavailableError|
        InternalServerErrorResponse {
    PersistedScanJob|error? loaded = loadScanJob(scanId);
    if loaded is error {
        log:printError("Unable to load persisted scan", loaded,
                requestId = requestId, scanId = scanId);
        return persistenceUnavailable(requestId);
    }
    if loaded is () {
        return scanNotFound(requestId);
    }
    PersistedScanJob job = loaded;

    if job.status == "QUEUED" || job.status == "RUNNING" {
        string? scannerId = job.scannerScanId;
        if scannerId is string {
            ScannerStatusResponse|ScannerFailure scannerResult =
                getScannerJob(scannerId, requestId);
            if scannerResult is ScannerFailure {
                if scannerResult.code == SCANNER_UNAVAILABLE {
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
                return internalServerError(requestId);
            }
            error? syncError = synchronizeScanJob(job, scannerResult);
            if syncError is error {
                log:printError("Unable to synchronize persisted scan", syncError,
                        requestId = requestId, scanId = scanId);
                return persistenceUnavailable(requestId);
            }
            PersistedScanJob|error? refreshed = loadScanJob(scanId);
            if refreshed is error || refreshed is () {
                return persistenceUnavailable(requestId);
            }
            job = refreshed;
        }
    }

    ScanPortResult[] ports = [];
    if job.status == "COMPLETED" {
        PersistedScanResult[]|error storedResults = loadScanResults(scanId);
        if storedResults is error {
            log:printError("Unable to load persisted scan results", storedResults,
                    requestId = requestId, scanId = scanId);
            return persistenceUnavailable(requestId);
        }
        ports = from PersistedScanResult port in storedResults
            select {
                address: port.address,
                port: port.port,
                state: <ScanPortState>port.state
            };
    }
    return persistedScanResponse(job, ports, requestId);
}

function persistedScanResponse(PersistedScanJob job, ScanPortResult[] ports,
        string requestId) returns ScanStatusOk {
    ScanJobStatus publicStatus = job.status == "COMPLETED" ? "completed" :
            job.status == "FAILED" || job.status == "BLOCKED" ? "failed" : "running";
    ScanResultData? result = ();
    if job.status == "COMPLETED" {
        result = {
            target: job.target,
            startPort: job.startPort,
            endPort: job.endPort,
            results: ports,
            durationNanos: <int>job.durationNanos
        };
    }
    ScanStatusData data = {
        id: job.id,
        status: publicStatus,
        target: job.target,
        startPort: job.startPort,
        endPort: job.endPort,
        createdAt: job.createdAt,
        updatedAt: job.updatedAt,
        result: result
    };
    return {headers: {requestId: requestId}, body: {success: true, data: data}};
}

function scanNotFound(string requestId) returns NotFoundError {
    return {
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
}

function persistenceUnavailable(string requestId) returns ServiceUnavailableError {
    return {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: PERSISTENCE_UNAVAILABLE,
                message: "Scan persistence is temporarily unavailable",
                requestId: requestId
            }
        }
    };
}

function internalServerError(string requestId) returns InternalServerErrorResponse {
    return {
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
