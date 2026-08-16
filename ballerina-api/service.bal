import ballerina/http;
import ballerina/lang.'string;
import ballerina/lang.runtime as runtime;
import ballerina/log;
import ballerina/uuid;

configurable int listenerPort = 9090;
configurable string serviceName = "securescan-api";
configurable int maxPortsPerScan = 1000;
configurable int maxRequestBodyBytes = 4096;

function init() returns error? {
    check validateAuthenticationConfiguration();
    check validateAsyncConfiguration(maxActiveScansPerOwner,
            reconciliationIntervalSeconds);
    check validateSecurityLimits(maxPortsPerScan, maxRequestBodyBytes);
    check validateDispatchLease(dispatchLeaseSeconds, scannerResponseTimeout);
    check validateTargetAuthorizationConfiguration();
    if persistenceEnabled {
        _ = start reconcileActiveScansInBackground();
    }
}

function reconcileActiveScansInBackground() {
    while persistenceEnabled {
        runtime:sleep(<decimal>reconciliationIntervalSeconds);
        PersistedScanJob[]|error activeJobs = loadActiveScanJobs(100);
        if activeJobs is error {
            log:printError("Unable to load scans for background reconciliation",
                    activeJobs);
            continue;
        }
        foreach PersistedScanJob job in activeJobs {
            string requestId = uuid:createType4AsString();
            _ = getPersistedScanStatus(job.id, job.ownerSubject, true, requestId);
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
            TooManyRequestsError|InternalServerErrorResponse|UnauthorizedError|
            ForbiddenError|PayloadTooLargeError {
        string requestId = uuid:createType4AsString();
        log:printInfo("Scan create request received",
                requestId = requestId, operation = "createScan");

        AuthContext|UnauthorizedError|ForbiddenError authenticated =
            authenticateRequest(httpRequest, requestId);
        AuthContext authContext;
        if authenticated is AuthContext {
            authContext = authenticated;
        } else {
            return authenticated;
        }

        byte[]|http:ClientError rawPayload = httpRequest.getBinaryPayload();
        if rawPayload is http:ClientError {
            return badRequest(INVALID_REQUEST, "Request body is unreadable", {}, requestId);
        }
        CreateScanRequest|BadRequestError|PayloadTooLargeError parsedRequest =
            parseCreateScanRequest(rawPayload, requestId);
        CreateScanRequest request;
        if parsedRequest is CreateScanRequest {
            request = parsedRequest;
        } else {
            return parsedRequest;
        }

        BadRequestError? validationError = validateCreateScanRequest(request, requestId);
        if validationError is BadRequestError {
            return validationError;
        }

        string publicScanId = uuid:createType4AsString();
        if persistenceEnabled {
            string? initialAllowedTargetId = ();
            if !targetAuthorizationTestBypass {
                // Validate once at admission, then repeat after taking the
                // dispatch lease. The second resolution is the authoritative
                // decision immediately before the scanner call.
                AuthorizedScanTarget|TargetAuthorizationFailure|error authorization =
                    authorizeScanTarget(authContext.subject, request);
                if authorization is error {
                    log:printError("Unable to authorize scan target",
                            requestId = requestId, scanId = publicScanId);
                    return persistenceUnavailable(requestId);
                }
                if authorization is TargetAuthorizationFailure {
                    error? auditError = insertBlockedScan(publicScanId,
                            authContext.subject, request, authorization.code,
                            requestId, authorization.allowedTargetId);
                    if auditError is error {
                        log:printError("Unable to audit blocked scan",
                                requestId = requestId, scanId = publicScanId);
                        return persistenceUnavailable(requestId);
                    }
                    return badRequest(BLOCKED_TARGET,
                            "The target is not permitted", {}, requestId);
                }
                initialAllowedTargetId = authorization.allowedTargetId;
                request.target = authorization.normalizedTarget;
            }
            QueuedScanInsertOutcome|error insertError =
                insertQueuedScan(publicScanId, authContext.subject, request,
                    requestId, initialAllowedTargetId);
            if insertError is error {
                log:printError("Unable to persist queued scan", insertError,
                        requestId = requestId, scanId = publicScanId);
                return persistenceUnavailable(requestId);
            }
            if insertError == "LIMIT_REACHED" {
                return jobLimitReached(requestId);
            }

            _ = start dispatchQueuedScanInBackground(publicScanId,
                    authContext.subject, request, requestId);
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

    resource function get api/v1/scans(http:Request httpRequest, int pageSize = 20,
            string? cursorCreatedAt = (), string? cursorId = (),
            string? ownerSubject = ())
            returns ScanHistoryOk|BadRequestError|ServiceUnavailableError|
            UnauthorizedError|ForbiddenError {
        string requestId = uuid:createType4AsString();
        AuthContext|UnauthorizedError|ForbiddenError authenticated =
            authenticateRequest(httpRequest, requestId);
        AuthContext authContext;
        if authenticated is AuthContext {
            authContext = authenticated;
        } else {
            return authenticated;
        }
        string selectedOwner = ownerSubject is string ? ownerSubject.trim() :
            authContext.subject;
        if selectedOwner == "" || selectedOwner.length() > 255 {
            return badRequest(INVALID_REQUEST, "Owner subject is invalid",
                    {"field": "ownerSubject"}, requestId);
        }
        if !canAccessOwner(authContext, selectedOwner) {
            return forbidden(requestId);
        }
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
            loadScanHistoryAfter(selectedOwner, cursorCreatedAt,
                    cursorId, pageSize) :
            loadScanHistory(selectedOwner, pageSize);
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

    resource function get api/v1/scans/[string scanId](http:Request httpRequest)
            returns ScanStatusOk|BadRequestError|NotFoundError|
            ServiceUnavailableError|InternalServerErrorResponse|UnauthorizedError|
            ForbiddenError {
        string requestId = uuid:createType4AsString();
        log:printInfo("Scan status request received",
                requestId = requestId, operation = "getScanStatus");

        AuthContext|UnauthorizedError|ForbiddenError authenticated =
            authenticateRequest(httpRequest, requestId);
        AuthContext authContext;
        if authenticated is AuthContext {
            authContext = authenticated;
        } else {
            return authenticated;
        }

        if !uuid:validate(scanId) {
            return badRequest(INVALID_SCAN_ID, "Scan ID must be a valid UUID",
                    {"field": "scanId"}, requestId);
        }

        if persistenceEnabled {
            return getPersistedScanStatus(scanId, authContext.subject,
                    authContext.admin, requestId);
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

    resource function get api/v1/admin/'allowed\-targets(http:Request httpRequest,
            boolean includeDisabled = false, int pageSize = 100)
            returns AllowedTargetListOk|BadRequestError|ServiceUnavailableError|
            UnauthorizedError|ForbiddenError {
        string requestId = uuid:createType4AsString();
        AuthContext|UnauthorizedError|ForbiddenError authenticated =
            authenticateRequest(httpRequest, requestId);
        AuthContext authContext;
        if authenticated is AuthContext {
            authContext = authenticated;
        } else {
            return authenticated;
        }
        ForbiddenError? adminError = requireAdmin(authContext, requestId);
        if adminError is ForbiddenError {
            return adminError;
        }
        if pageSize < 1 || pageSize > 100 {
            return badRequest(INVALID_REQUEST,
                    "Page size must be between 1 and 100",
                    {"field": "pageSize", min: 1, max: 100}, requestId);
        }
        PersistedAllowedTarget[]|error loaded =
            loadAllowedTargets(includeDisabled, pageSize);
        if loaded is error {
            log:printError("Unable to load allowed targets", loaded,
                    requestId = requestId);
            return persistenceUnavailable(requestId);
        }
        AllowedTargetData[] items = from PersistedAllowedTarget item in loaded
            select allowedTargetData(item);
        AllowedTargetListData data = {items: items, pageSize: pageSize};
        return {headers: {requestId: requestId}, body: {success: true, data: data}};
    }

    resource function post api/v1/admin/'allowed\-targets(http:Request httpRequest)
            returns AllowedTargetCreated|BadRequestError|PayloadTooLargeError|
            ConflictError|ServiceUnavailableError|UnauthorizedError|ForbiddenError {
        string requestId = uuid:createType4AsString();
        AuthContext|UnauthorizedError|ForbiddenError authenticated =
            authenticateRequest(httpRequest, requestId);
        AuthContext authContext;
        if authenticated is AuthContext {
            authContext = authenticated;
        } else {
            return authenticated;
        }
        ForbiddenError? adminError = requireAdmin(authContext, requestId);
        if adminError is ForbiddenError {
            return adminError;
        }
        byte[]|http:ClientError rawPayload = httpRequest.getBinaryPayload();
        if rawPayload is http:ClientError {
            return badRequest(INVALID_REQUEST, "Request body is unreadable", {},
                                                                             requestId);
        }
        CreateAllowedTargetRequest|BadRequestError|PayloadTooLargeError parsed =
            parseAllowedTargetRequest(rawPayload, requestId);
        CreateAllowedTargetRequest request;
        if parsed is CreateAllowedTargetRequest {
            request = parsed;
        } else {
            return parsed;
        }
        string|BadRequestError normalized =
            validateAllowedTargetRequest(request, requestId);
        if normalized is BadRequestError {
            return normalized;
        }
        if request.targetKind != "HOSTNAME" {
            boolean|error networkValid =
                validateNetworkAllowedTarget(normalized, request.targetKind);
            if networkValid is error {
                return persistenceUnavailable(requestId);
            }
            if !networkValid {
                return badRequest(INVALID_TARGET,
                        "Target does not match the selected target kind",
                        {"field": "target"}, requestId);
            }
        }
        string targetId = uuid:createType4AsString();
        AllowedTargetInsertOutcome|error inserted = insertAllowedTarget(targetId,
                authContext.subject, request, normalized, requestId);
        if inserted is error {
            log:printError("Unable to create allowed target", inserted,
                    requestId = requestId);
            return persistenceUnavailable(requestId);
        }
        if inserted == "ALREADY_EXISTS" {
            return allowedTargetConflict(requestId);
        }
        PersistedAllowedTarget|error? loaded = loadAllowedTarget(targetId);
        if loaded is error || loaded is () {
            return persistenceUnavailable(requestId);
        }
        return {
            headers: {requestId: requestId},
            body: {success: true, data: allowedTargetData(loaded)}
        };
    }

    resource function delete api/v1/admin/'allowed\-targets/[string targetId](
            http:Request httpRequest)
            returns AllowedTargetOk|BadRequestError|NotFoundError|
            ServiceUnavailableError|UnauthorizedError|ForbiddenError {
        string requestId = uuid:createType4AsString();
        AuthContext|UnauthorizedError|ForbiddenError authenticated =
            authenticateRequest(httpRequest, requestId);
        AuthContext authContext;
        if authenticated is AuthContext {
            authContext = authenticated;
        } else {
            return authenticated;
        }
        ForbiddenError? adminError = requireAdmin(authContext, requestId);
        if adminError is ForbiddenError {
            return adminError;
        }
        if !uuid:validate(targetId) {
            return badRequest(INVALID_REQUEST,
                    "Allowed target ID must be a valid UUID",
                    {"field": "targetId"}, requestId);
        }
        AllowedTargetDisableOutcome|error disabled = disableAllowedTarget(targetId,
                authContext.subject, requestId);
        if disabled is error {
            log:printError("Unable to disable allowed target", disabled,
                    requestId = requestId, allowedTargetId = targetId);
            return persistenceUnavailable(requestId);
        }
        if disabled == "NOT_FOUND" {
            return allowedTargetNotFound(requestId);
        }
        PersistedAllowedTarget|error? loaded = loadAllowedTarget(targetId);
        if loaded is error || loaded is () {
            return persistenceUnavailable(requestId);
        }
        return {
            headers: {requestId: requestId},
            body: {success: true, data: allowedTargetData(loaded)}
        };
    }
}

function dispatchQueuedScanInBackground(string publicScanId, string ownerSubject,
        CreateScanRequest request, string requestId) {
    error? dispatchError = dispatchQueuedScan(publicScanId, ownerSubject, request,
            requestId);
    if dispatchError is error {
        log:printError("Background scanner dispatch failed", dispatchError,
                requestId = requestId, scanId = publicScanId);
    }
}

function dispatchQueuedScan(string publicScanId, string ownerSubject,
        CreateScanRequest request, string requestId) returns error? {
    check validateDispatchLease(dispatchLeaseSeconds, scannerResponseTimeout);
    string leaseToken = uuid:createType4AsString();
    ScanUpdateOutcome|error claim = claimScanDispatch(publicScanId, leaseToken);
    if claim is error {
        return claim;
    }
    if claim == "UNCHANGED" {
        return;
    }
    if !targetAuthorizationTestBypass {
        // Resolve and authorize at the dispatch boundary, not only when the job
        // was queued. This narrows the DNS-rebinding window and catches rules
        // disabled while a job was waiting.
        AuthorizedScanTarget|TargetAuthorizationFailure|error authorization =
            authorizeScanTarget(ownerSubject, request);
        if authorization is error {
            return authorization;
        }
        if authorization is TargetAuthorizationFailure {
            _ = check markScanDispatchFailed(publicScanId, ownerSubject,
                    authorization.code, true, leaseToken, requestId);
            return;
        }
        ScanUpdateOutcome attached = check attachAllowedTargetToDispatch(
                publicScanId, authorization.allowedTargetId, leaseToken);
        if attached == "UNCHANGED" {
            _ = check markScanDispatchFailed(publicScanId, ownerSubject,
                    BLOCKED_TARGET, true, leaseToken, requestId);
            return;
        }
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
                ownerSubject, scannerResult.code,
                scannerResult.code == BLOCKED_TARGET,
                leaseToken, requestId);
        if failed is error {
            return failed;
        }
        return;
    }
    ScanUpdateOutcome|error dispatched =
        markScanDispatched(publicScanId, ownerSubject, scannerResult.id,
            leaseToken, requestId);
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
    if activeLimit != 1 {
        return error("maxActiveScansPerOwner must be exactly one");
    }
    if intervalSeconds < 1 {
        return error("reconciliationIntervalSeconds must be greater than zero");
    }
}

function validateSecurityLimits(int portLimit, int bodyLimit) returns error? {
    if portLimit < 1 || portLimit > 1000 {
        return error("maxPortsPerScan must be between 1 and 1000");
    }
    if bodyLimit < 1 || bodyLimit > 4096 {
        return error("maxRequestBodyBytes must be between 1 and 4096");
    }
}

function getPersistedScanStatus(string scanId, string actorSubject, boolean admin,
        string requestId)
        returns ScanStatusOk|NotFoundError|ServiceUnavailableError|
        InternalServerErrorResponse {
    PersistedScanJob|error? loaded =
        loadScanJobForActor(scanId, actorSubject, admin);
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
            error? recoveryError = dispatchQueuedScan(job.id, job.ownerSubject,
                    recoveryRequest, requestId);
            if recoveryError is error {
                log:printError("Unable to recover queued scan dispatch", recoveryError,
                        requestId = requestId, scanId = scanId);
                return persistenceUnavailable(requestId);
            }
            PersistedScanJob|error? recovered =
                loadScanJobForActor(scanId, actorSubject, admin);
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
                    markScanSynchronizationFailed(job.id, job.ownerSubject,
                        scannerResult.code, requestId);
                if failed is error {
                    return persistenceUnavailable(requestId);
                }
                PersistedScanJob|error? failedJob =
                    loadScanJobForActor(scanId, actorSubject, admin);
                if failedJob is error || failedJob is () {
                    return persistenceUnavailable(requestId);
                }
                return persistedScanResponse(failedJob, [], requestId);
            }
            if !scannerResponseMatchesJob(job, scannerId, scannerResult) {
                ScanUpdateOutcome|error failed =
                    markScanSynchronizationFailed(job.id, job.ownerSubject,
                        INTERNAL_ERROR, requestId);
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
                loadScanJobForActor(scanId, actorSubject, admin);
            if refreshed is error || refreshed is () {
                return persistenceUnavailable(requestId);
            }
            job = refreshed;
        }
    }

    ScanPortResult[] ports = [];
    if job.status == "COMPLETED" {
        PersistedScanResult[]|error storedResults =
            loadScanResultsForActor(scanId, actorSubject, admin);
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
        headers: {requestId: requestId, retryAfter: "5"},
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

function requestTooLarge(string requestId) returns PayloadTooLargeError {
    return {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: REQUEST_TOO_LARGE,
                message: "The API request body is too large",
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
                message: "SecureScan persistence is temporarily unavailable",
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
    int portCount = request.endPort - request.startPort + 1;
    if portCount > maxPortsPerScan {
        return badRequest(INVALID_PORT_RANGE,
                "A scan can include at most 1000 ports",
                {"field": "endPort", "maxPorts": maxPortsPerScan}, requestId);
    }
    if !request.authorized {
        return badRequest(BLOCKED_TARGET,
                "Authorized-use confirmation is required before creating a scan",
                {"field": "authorized"}, requestId);
    }
    return ();
}

function parseCreateScanRequest(byte[] rawPayload, string requestId)
        returns CreateScanRequest|BadRequestError|PayloadTooLargeError {
    if rawPayload.length() > maxRequestBodyBytes {
        return requestTooLarge(requestId);
    }
    string|error textPayload = 'string:fromBytes(rawPayload);
    if textPayload is error {
        return badRequest(INVALID_REQUEST, "Request body must be UTF-8 JSON", {}, requestId);
    }
    json|error payload = textPayload.fromJsonString();
    if payload is error {
        return badRequest(INVALID_REQUEST,
                "Request body must contain valid JSON", {}, requestId);
    }
    CreateScanRequest|error boundRequest = payload.cloneWithType();
    if boundRequest is error {
        return badRequest(INVALID_REQUEST,
                "Request body does not match the scan contract", {}, requestId);
    }
    return boundRequest;
}

function parseAllowedTargetRequest(byte[] rawPayload, string requestId)
        returns CreateAllowedTargetRequest|BadRequestError|PayloadTooLargeError {
    if rawPayload.length() > maxRequestBodyBytes {
        return requestTooLarge(requestId);
    }
    string|error textPayload = 'string:fromBytes(rawPayload);
    if textPayload is error {
        return badRequest(INVALID_REQUEST, "Request body must be UTF-8 JSON", {},
                                                                              requestId);
    }
    json|error payload = textPayload.fromJsonString();
    if payload is error {
        return badRequest(INVALID_REQUEST,
                "Request body must contain valid JSON", {}, requestId);
    }
    CreateAllowedTargetRequest|error boundRequest = payload.cloneWithType();
    if boundRequest is error {
        return badRequest(INVALID_REQUEST,
                "Request body does not match the allowed-target contract", {},
                                                                           requestId);
    }
    return boundRequest;
}

function validateAllowedTargetRequest(CreateAllowedTargetRequest request,
        string requestId) returns string|BadRequestError {
    string target = request.target.trim();
    if target == "" || target.length() > 253 {
        return badRequest(INVALID_TARGET,
                "Target must contain between 1 and 253 characters",
                {"field": "target"}, requestId);
    }
    if (request.startPort is int) != (request.endPort is int) {
        return badRequest(INVALID_PORT_RANGE,
                "Both startPort and endPort are required when restricting ports",
                {"field": "ports"}, requestId);
    }
    int? possibleStartPort = request.startPort;
    int? possibleEndPort = request.endPort;
    if possibleStartPort is int && possibleEndPort is int {
        int startPort = possibleStartPort;
        int endPort = possibleEndPort;
        if startPort < 1 || endPort > 65535 || startPort > endPort {
            return badRequest(INVALID_PORT_RANGE,
                    "Allowed-target ports must form a valid inclusive range",
                    {startPort: startPort, endPort: endPort}, requestId);
        }
    }
    if request.targetKind == "HOSTNAME" {
        string hostname = 'string:toLowerAscii(target);
        if !validExactHostname(hostname) {
            return badRequest(INVALID_TARGET,
                    "Target must be an exact DNS hostname",
                    {"field": "target"}, requestId);
        }
        return hostname;
    }
    if request.targetKind == "IP" && target.includes("/") {
        return badRequest(INVALID_TARGET,
                "Exact IP targets cannot contain a prefix length",
                {"field": "target"}, requestId);
    }
    if request.targetKind == "CIDR" && !target.includes("/") {
        return badRequest(INVALID_TARGET,
                "CIDR targets require an explicit prefix length",
                {"field": "target"}, requestId);
    }
    return target;
}

function validExactHostname(string hostname) returns boolean {
    if hostname.length() < 1 || hostname.length() > 253 ||
            hostname.startsWith(".") || hostname.endsWith(".") ||
            hostname.includes("..") {
        return false;
    }
    string[] labels = re `\.`.split(hostname);
    foreach string label in labels {
        if label.length() < 1 || label.length() > 63 ||
                label.startsWith("-") || label.endsWith("-") {
            return false;
        }
        foreach int codePoint in label.toCodePointInts() {
            boolean allowed = (codePoint >= 97 && codePoint <= 122) ||
                (codePoint >= 48 && codePoint <= 57) || codePoint == 45;
            if !allowed {
                return false;
            }
        }
    }
    return true;
}

function allowedTargetData(PersistedAllowedTarget target)
        returns AllowedTargetData {
    return {
        id: target.id,
        targetKind: <AllowedTargetKind>target.targetKind,
        target: target.target,
        startPort: target.startPort,
        endPort: target.endPort,
        enabled: target.enabled,
        createdBySubject: target.createdBySubject,
        createdAt: target.createdAt,
        updatedAt: target.updatedAt
    };
}

function allowedTargetConflict(string requestId) returns ConflictError {
    return {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: ALLOWED_TARGET_EXISTS,
                message: "An enabled allowed target already has this value and port range",
                requestId: requestId
            }
        }
    };
}

function allowedTargetNotFound(string requestId) returns NotFoundError {
    return {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: ALLOWED_TARGET_NOT_FOUND,
                message: "Enabled allowed target not found",
                requestId: requestId
            }
        }
    };
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
