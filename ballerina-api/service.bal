import ballerina/http;
import ballerina/log;
import ballerina/lang.runtime as runtime;
import ballerina/uuid;

configurable int listenerPort = 9090;
configurable string serviceName = "securescan-api";

function init() returns error? {
    check validateAsyncConfiguration(maxActiveScansPerOwner,
            reconciliationIntervalSeconds);
    check validateDispatchLease(dispatchLeaseSeconds, scannerResponseTimeout);
    if persistenceEnabled {
        _ = start reconcileActiveScansInBackground();
    }
}

function reconcileActiveScansInBackground() {
    while persistenceEnabled {
        runtime:sleep(<decimal>reconciliationIntervalSeconds);
        PersistedScanJob[]|error activeJobs = loadActiveScanJobs(
                developmentOwnerSubject, maxActiveScansPerOwner);
        if activeJobs is error {
            log:printError("Unable to load scans for background reconciliation",
                    activeJobs);
            continue;
        }
        foreach PersistedScanJob job in activeJobs {
            string requestId = uuid:createType4AsString();
            _ = getPersistedScanStatus(job.id, requestId);
        }
    }
}

service / on new http:Listener(listenerPort) {
    resource function get health() returns HealthOk {
        HealthData healthData = {status: "ok", serviceName: serviceName};
        return {body: {success: true, data: healthData}};
    }

    resource function post api/v1/scans(http:Request httpRequest)
            returns CreateScanAccepted|BadRequestError|ServiceUnavailableError|
            TooManyRequestsError|InternalServerErrorResponse {
        string requestId = uuid:createType4AsString();
        log:printInfo("Scan create request received",
                requestId = requestId, operation = "createScan");

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
            QueuedScanInsertOutcome|error insertError =
                insertQueuedScan(publicScanId, request, requestId);
            if insertError is error {
                log:printError("Unable to persist queued scan", insertError,
                        requestId = requestId, scanId = publicScanId);
                return persistenceUnavailable(requestId);
            }
            if insertError == "LIMIT_REACHED" {
                return jobLimitReached(requestId);
            }

            _ = start dispatchQueuedScanInBackground(publicScanId, request,
                    requestId);
            CreateScanData queuedData = {
                id: publicScanId,
                status: "queued",
                target: request.target.trim(),
                startPort: request.startPort,
                endPort: request.endPort
            };
            return {
                headers: {requestId: requestId},
                body: {success: true, data: queuedData}
            };
        }

        ScannerCreateResponse|ScannerFailure scannerResult =
            createScannerJob(request, requestId, publicScanId);
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

    resource function get api/v1/scans(int pageSize = 20,
            string? cursorCreatedAt = (), string? cursorId = ())
            returns ScanHistoryOk|BadRequestError|ServiceUnavailableError {
        string requestId = uuid:createType4AsString();
        if pageSize < 1 || pageSize > 100 {
            return badRequest(INVALID_REQUEST, "Page size must be between 1 and 100",
                    {"field": "pageSize", min: 1, max: 100}, requestId);
        }
        if (cursorCreatedAt is string) != (cursorId is string) ||
                (cursorId is string && !uuid:validate(cursorId)) {
            return badRequest(INVALID_REQUEST,
                    "Both cursorCreatedAt and a valid cursorId are required",
                    {"field": "cursor"}, requestId);
        }
        PersistedScanHistoryItem[]|error loaded =
            cursorCreatedAt is string && cursorId is string ?
            loadScanHistoryAfter(developmentOwnerSubject, cursorCreatedAt,
                    cursorId, pageSize) :
            loadScanHistory(developmentOwnerSubject, pageSize);
        if loaded is error {
            log:printError("Unable to load scan history", loaded,
                    requestId = requestId);
            return persistenceUnavailable(requestId);
        }
        ScanHistoryItem[] items = from PersistedScanHistoryItem item in loaded
            select persistedHistoryItem(item);
        ScanHistoryData data = {items: items, pageSize: pageSize};
        return {headers: {requestId: requestId}, body: {success: true, data: data}};
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

function dispatchQueuedScanInBackground(string publicScanId,
        CreateScanRequest request, string requestId) {
    error? dispatchError = dispatchQueuedScan(publicScanId, request, requestId);
    if dispatchError is error {
        log:printError("Background scanner dispatch failed", dispatchError,
                requestId = requestId, scanId = publicScanId);
    }
}

function dispatchQueuedScan(string publicScanId, CreateScanRequest request,
        string requestId) returns error? {
    check validateDispatchLease(dispatchLeaseSeconds, scannerResponseTimeout);
    string leaseToken = uuid:createType4AsString();
    ScanUpdateOutcome|error claim = claimScanDispatch(publicScanId, leaseToken);
    if claim is error {
        return claim;
    }
    if claim == "UNCHANGED" {
        return;
    }
    ScannerCreateResponse|ScannerFailure scannerResult =
        createScannerJob(request, requestId, publicScanId);
    if scannerResult is ScannerFailure {
        if scannerResult.code == SCANNER_UNAVAILABLE ||
                scannerResult.code == JOB_LIMIT_REACHED {
            log:printWarn("Scanner dispatch deferred for recovery",
                    requestId = requestId, scanId = publicScanId);
            return;
        }
        ScanUpdateOutcome|error failed = markScanDispatchFailed(publicScanId,
                scannerResult.code, scannerResult.code == BLOCKED_TARGET,
                leaseToken, requestId);
        if failed is error {
            return failed;
        }
        return;
    }
    ScanUpdateOutcome|error dispatched =
        markScanDispatched(publicScanId, scannerResult.id, leaseToken, requestId);
    if dispatched is error {
        return dispatched;
    }
}

function validateDispatchLease(int leaseSeconds, decimal responseTimeout)
        returns error? {
    if <decimal>leaseSeconds <= responseTimeout {
        return error("dispatch lease must exceed scanner response timeout");
    }
}

function validateAsyncConfiguration(int activeLimit, int intervalSeconds)
        returns error? {
    if activeLimit < 1 {
        return error("maxActiveScansPerOwner must be greater than zero");
    }
    if intervalSeconds < 1 {
        return error("reconciliationIntervalSeconds must be greater than zero");
    }
}

function getPersistedScanStatus(string scanId, string requestId)
        returns ScanStatusOk|NotFoundError|ServiceUnavailableError|
        InternalServerErrorResponse {
    PersistedScanJob|error? loaded =
        loadScanJob(scanId, developmentOwnerSubject);
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
        if job.status == "QUEUED" && scannerId is () {
            CreateScanRequest recoveryRequest = {
                target: job.target,
                startPort: job.startPort,
                endPort: job.endPort,
                authorized: true
            };
            error? recoveryError = dispatchQueuedScan(job.id, recoveryRequest,
                    requestId);
            if recoveryError is error {
                log:printError("Unable to recover queued scan dispatch", recoveryError,
                        requestId = requestId, scanId = scanId);
                return persistenceUnavailable(requestId);
            }
            PersistedScanJob|error? recovered =
                loadScanJob(scanId, developmentOwnerSubject);
            if recovered is error || recovered is () {
                return persistenceUnavailable(requestId);
            }
            job = recovered;
            scannerId = job.scannerScanId;
        }
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
                ScanUpdateOutcome|error failed =
                    markScanSynchronizationFailed(job.id, scannerResult.code,
                            requestId);
                if failed is error {
                    return persistenceUnavailable(requestId);
                }
                PersistedScanJob|error? failedJob =
                    loadScanJob(scanId, developmentOwnerSubject);
                if failedJob is error || failedJob is () {
                    return persistenceUnavailable(requestId);
                }
                return persistedScanResponse(failedJob, [], requestId);
            }
            if !scannerResponseMatchesJob(job, scannerId, scannerResult) {
                ScanUpdateOutcome|error failed =
                    markScanSynchronizationFailed(job.id, INTERNAL_ERROR,
                            requestId);
                if failed is error {
                    return persistenceUnavailable(requestId);
                }
                log:printError("Scanner response did not match persisted job",
                        requestId = requestId, scanId = scanId);
                return internalServerError(requestId);
            }
            error? syncError = synchronizeScanJob(job, scannerResult, requestId);
            if syncError is error {
                log:printError("Unable to synchronize persisted scan", syncError,
                        requestId = requestId, scanId = scanId);
                return persistenceUnavailable(requestId);
            }
            PersistedScanJob|error? refreshed =
                loadScanJob(scanId, developmentOwnerSubject);
            if refreshed is error || refreshed is () {
                return persistenceUnavailable(requestId);
            }
            job = refreshed;
        }
    }

    ScanPortResult[] ports = [];
    if job.status == "COMPLETED" {
        PersistedScanResult[]|error storedResults =
            loadScanResults(scanId, developmentOwnerSubject);
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

function scannerResponseMatchesJob(PersistedScanJob job, string scannerId,
        ScannerStatusResponse scanner) returns boolean {
    if scanner.id != scannerId || scanner.target != job.target ||
            scanner.startPort != job.startPort || scanner.endPort != job.endPort {
        return false;
    }
    ScannerResult? possibleResult = scanner.result;
    if possibleResult is ScannerResult {
        return possibleResult.target == job.target &&
            possibleResult.startPort == job.startPort &&
            possibleResult.endPort == job.endPort;
    }
    return true;
}

function persistedScanResponse(PersistedScanJob job, ScanPortResult[] ports,
        string requestId) returns ScanStatusOk {
    ScanJobStatus publicStatus = persistedPublicStatus(job.status);
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
        failureCode: job.failureCode,
        result: result
    };
    return {headers: {requestId: requestId}, body: {success: true, data: data}};
}

function persistedPublicStatus(string status) returns ScanJobStatus {
    return status == "QUEUED" ? "queued" : status == "COMPLETED" ? "completed" :
                status == "BLOCKED" ? "blocked" : status == "FAILED" ? "failed" : "running";
}

function persistedHistoryItem(PersistedScanHistoryItem item)
        returns ScanHistoryItem {
    return {
        id: item.id,
        status: persistedPublicStatus(item.status),
        target: item.target,
        startPort: item.startPort,
        endPort: item.endPort,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt
    };
}

function jobLimitReached(string requestId) returns TooManyRequestsError {
    return {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: JOB_LIMIT_REACHED,
                message: "Too many active scans; wait for one to finish",
                requestId: requestId
            }
        }
    };
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
        returns BadRequestError|ServiceUnavailableError|TooManyRequestsError|
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
    if failure.code == JOB_LIMIT_REACHED {
        return jobLimitReached(requestId);
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
