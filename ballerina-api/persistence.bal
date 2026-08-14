import ballerina/sql;
import ballerina/uuid;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

configurable boolean persistenceEnabled = true;
configurable string databaseHost = "localhost";
configurable int databasePort = 5432;
configurable string databaseName = "securescan_dev";
configurable string databaseUser = "securescan";
configurable string databasePassword = "securescan_dev_only";
configurable int maxActiveScansPerOwner = 5;
configurable int dispatchLeaseSeconds = 15;
configurable int reconciliationIntervalSeconds = 5;

final postgresql:Client? databaseClient = persistenceEnabled ? check new (
        host = databaseHost,
        port = databasePort,
        username = databaseUser,
        password = databasePassword,
        database = databaseName,
        connectionPool = {maxOpenConnections: 10}
    ) : ();

type PersistedScanJob record {|
    string id;
    string ownerSubject;
    string? scannerScanId = ();
    string target;
    int startPort;
    int endPort;
    string status;
    string? failureCode = ();
    int? durationNanos = ();
    string createdAt;
    string updatedAt;
|};

type PersistedScanResult record {|
    string address;
    int port;
    string state;
|};

type PersistedScanHistoryItem record {|
    string id;
    string target;
    int startPort;
    int endPort;
    string status;
    string createdAt;
    string updatedAt;
|};

type LockedScanJob record {|
    string id;
|};

type ScanUpdateOutcome "APPLIED"|"UNCHANGED";

type AuditActorType "USER"|"SERVICE";

type AuditAction "SCAN_REQUESTED"|"SCAN_BLOCKED"|"SCAN_STARTED"|
    "SCAN_COMPLETED"|"SCAN_FAILED";

type AuditOutcome "SUCCESS"|"DENIED"|"FAILURE";

type QueuedScanInsertOutcome "CREATED"|"LIMIT_REACHED";

type ActiveScanCount record {|
    int activeCount;
|};

type AdvisoryLockResult record {|
    string locked;
|};

function insertQueuedScan(string id, string ownerSubject, CreateScanRequest request,
        string requestId)
        returns QueuedScanInsertOutcome|error {
    postgresql:Client db = check getDatabaseClient();
    string target = request.target.trim();
    transaction {

        stream<AdvisoryLockResult, sql:Error?> lockStream = db->query(`
            SELECT pg_advisory_xact_lock(
                hashtext(${ownerSubject}))::text AS "locked"`);
        AdvisoryLockResult[] lockRows = check from AdvisoryLockResult lockResult in lockStream
            select lockResult;
        _ = lockRows;
        stream<ActiveScanCount, sql:Error?> countStream = db->query(`
            SELECT count(*)::bigint AS "activeCount"
              FROM scan_jobs
             WHERE owner_subject = ${ownerSubject}
               AND status IN ('QUEUED', 'RUNNING')`);
        ActiveScanCount[] counts = check from ActiveScanCount count in countStream
            select count;
        boolean admitted = counts[0].activeCount < maxActiveScansPerOwner;
        if admitted {
            _ = check db->execute(`
                INSERT INTO scan_jobs
                    (id, owner_subject, target, start_port, end_port, status)
                VALUES (CAST(${id} AS uuid), ${ownerSubject}, ${target},
                        ${request.startPort}, ${request.endPort}, 'QUEUED')`);
            json metadata = {
                startPort: request.startPort,
                endPort: request.endPort
            };
            check insertAuditEvent(db, "USER", ownerSubject, ownerSubject,
                    "SCAN_REQUESTED", "SUCCESS", requestId, id, metadata);
        }
        check commit;
        if !admitted {
            return "LIMIT_REACHED";
        }
    }
    return "CREATED";
}

function claimScanDispatch(string id, string leaseToken)
        returns ScanUpdateOutcome|error {
    postgresql:Client db = check getDatabaseClient();
    sql:ExecutionResult update = check db->execute(`
        UPDATE scan_jobs
           SET dispatch_lease_token = CAST(${leaseToken} AS uuid),
               dispatch_lease_expires_at = CURRENT_TIMESTAMP
                   + make_interval(secs => ${dispatchLeaseSeconds}),
               updated_at = CURRENT_TIMESTAMP
         WHERE id = CAST(${id} AS uuid)
           AND status = 'QUEUED' AND scanner_scan_id IS NULL
           AND (dispatch_lease_expires_at IS NULL
                OR dispatch_lease_expires_at <= CURRENT_TIMESTAMP)`);
    return scanUpdateOutcome(update);
}

function markScanDispatched(string id, string ownerSubject, string scannerScanId,
        string leaseToken, string requestId)
        returns ScanUpdateOutcome|error {
    postgresql:Client db = check getDatabaseClient();
    ScanUpdateOutcome outcome = "UNCHANGED";
    transaction {
        sql:ExecutionResult update = check db->execute(`
            UPDATE scan_jobs
               SET scanner_scan_id = CAST(${scannerScanId} AS uuid),
                   status = 'RUNNING', started_at = CURRENT_TIMESTAMP,
                   dispatch_lease_token = NULL, dispatch_lease_expires_at = NULL,
                   updated_at = CURRENT_TIMESTAMP
             WHERE id = CAST(${id} AS uuid) AND status = 'QUEUED'
               AND dispatch_lease_token = CAST(${leaseToken} AS uuid)`);
        outcome = check scanUpdateOutcome(update);
        if outcome == "APPLIED" {
            check insertAuditEvent(db, "SERVICE", serviceName, ownerSubject,
                    "SCAN_STARTED", "SUCCESS", requestId, id, {});
        }
        check commit;
    }
    return outcome;
}

function markScanDispatchFailed(string id, string ownerSubject, string failureCode,
        boolean blocked, string leaseToken, string requestId)
        returns ScanUpdateOutcome|error {
    postgresql:Client db = check getDatabaseClient();
    string status = blocked ? "BLOCKED" : "FAILED";
    ScanUpdateOutcome updateOutcome = "UNCHANGED";
    transaction {
        sql:ExecutionResult update = check db->execute(`
            UPDATE scan_jobs
               SET status = ${status}, failure_code = ${failureCode},
                   dispatch_lease_token = NULL, dispatch_lease_expires_at = NULL,
                   finished_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
             WHERE id = CAST(${id} AS uuid) AND status = 'QUEUED'
               AND dispatch_lease_token = CAST(${leaseToken} AS uuid)`);
        updateOutcome = check scanUpdateOutcome(update);
        if updateOutcome == "APPLIED" {
            json metadata = {failureCode: failureCode};
            check insertAuditEvent(db, "SERVICE", serviceName, ownerSubject,
                    blocked ? "SCAN_BLOCKED" : "SCAN_FAILED",
                    blocked ? "DENIED" : "FAILURE", requestId, id, metadata);
        }
        check commit;
    }
    return updateOutcome;
}

function markScanSynchronizationFailed(string id, string ownerSubject,
        string failureCode, string requestId)
        returns ScanUpdateOutcome|error {
    postgresql:Client db = check getDatabaseClient();
    ScanUpdateOutcome outcome = "UNCHANGED";
    transaction {
        sql:ExecutionResult update = check db->execute(`
            UPDATE scan_jobs
               SET status = 'FAILED', failure_code = ${failureCode},
                   finished_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
             WHERE id = CAST(${id} AS uuid)
               AND status IN ('QUEUED', 'RUNNING')`);
        outcome = check scanUpdateOutcome(update);
        if outcome == "APPLIED" {
            json metadata = {failureCode: failureCode};
            check insertAuditEvent(db, "SERVICE", serviceName, ownerSubject,
                    "SCAN_FAILED", "FAILURE", requestId, id, metadata);
        }
        check commit;
    }
    return outcome;
}

function loadScanJobForActor(string id, string actorSubject, boolean admin)
        returns PersistedScanJob|error? {
    postgresql:Client db = check getDatabaseClient();
    stream<PersistedScanJob, sql:Error?> rowStream =
        db->query(`
            SELECT id::text AS "id", owner_subject AS "ownerSubject",
                   scanner_scan_id::text AS "scannerScanId",
                   target AS "target", start_port AS "startPort",
                   end_port AS "endPort", status AS "status",
                   failure_code AS "failureCode",
                   duration_nanos AS "durationNanos",
                   to_char(created_at AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "createdAt",
                   to_char(updated_at AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "updatedAt"
             FROM scan_jobs
             WHERE id = CAST(${id} AS uuid)
               AND (${admin} OR owner_subject = ${actorSubject})`);
    PersistedScanJob[] rows = check from PersistedScanJob row in rowStream
        select row;
    return rows.length() == 0 ? () : rows[0];
}

function loadActiveScanJobs(int pageSize)
        returns PersistedScanJob[]|error {
    if pageSize < 1 {
        return error("active scan reconciliation limit must be positive");
    }
    postgresql:Client db = check getDatabaseClient();
    stream<PersistedScanJob, sql:Error?> rowStream = db->query(`
        SELECT id::text AS "id", owner_subject AS "ownerSubject",
               scanner_scan_id::text AS "scannerScanId",
               target AS "target", start_port AS "startPort",
               end_port AS "endPort", status AS "status",
               failure_code AS "failureCode",
               duration_nanos AS "durationNanos",
               to_char(created_at AT TIME ZONE 'UTC',
                       'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "createdAt",
               to_char(updated_at AT TIME ZONE 'UTC',
                       'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "updatedAt"
          FROM scan_jobs
         WHERE status IN ('QUEUED', 'RUNNING')
         ORDER BY created_at, id
         LIMIT ${pageSize}`);
    return check from PersistedScanJob row in rowStream select row;
}

function synchronizeScanJob(PersistedScanJob job, ScannerStatusResponse scanner,
        string requestId)
        returns error? {
    postgresql:Client db = check getDatabaseClient();
    if scanner.status == "accepted" || scanner.status == "running" {
        return;
    }
    if scanner.status == "failed" {
        _ = check markScanSynchronizationFailed(job.id, job.ownerSubject,
                "SCANNER_FAILED",
                requestId);
        return;
    }

    ScannerResult result = <ScannerResult>scanner.result;
    transaction {
        
        stream<LockedScanJob, sql:Error?> lockStream = db->query(`
            SELECT id::text AS "id"
              FROM scan_jobs
             WHERE id = CAST(${job.id} AS uuid)
               AND owner_subject = ${job.ownerSubject}
               AND status IN ('QUEUED', 'RUNNING')
             FOR UPDATE`);
        LockedScanJob[] activeJobs = check from LockedScanJob activeJob in lockStream
            select activeJob;

        if activeJobs.length() == 1 {
            sql:ParameterizedQuery[] resultInserts =
                from ScannerPortResult port in result.results
            select `
                    INSERT INTO scan_results
                        (scan_job_id, address, port, state, observed_at)
                    VALUES (CAST(${job.id} AS uuid), CAST(${port.address} AS inet),
                            ${port.port}, upper(${port.state}), CURRENT_TIMESTAMP)
                    ON CONFLICT (scan_job_id, address, port) DO NOTHING`;
            if resultInserts.length() > 0 {
                _ = check db->batchExecute(resultInserts);
            }
            sql:ExecutionResult completion = check db->execute(`
                UPDATE scan_jobs
                   SET status = 'COMPLETED', duration_nanos = ${result.duration},
                       finished_at = CURRENT_TIMESTAMP,
                       updated_at = CURRENT_TIMESTAMP
                 WHERE id = CAST(${job.id} AS uuid)
                   AND status IN ('QUEUED', 'RUNNING')`);
            check requireAppliedUpdate(completion,
                    "active scan could not be marked completed");
            json metadata = {
                resultCount: result.results.length(),
                durationNanos: result.duration
            };
            check insertAuditEvent(db, "SERVICE", serviceName, job.ownerSubject,
                    "SCAN_COMPLETED", "SUCCESS", requestId, job.id, metadata);
        }
        check commit;
    }
}

function insertAuditEvent(postgresql:Client db, AuditActorType actorType,
        string actorSubject, string ownerSubject, AuditAction action, AuditOutcome outcome,
        string requestId, string scanId, json metadata) returns error? {
    string eventId = uuid:createType4AsString();
    string metadataJson = metadata.toJsonString();
    _ = check db->execute(`
        INSERT INTO audit_logs
            (id, actor_type, actor_subject, owner_subject, action, outcome,
             request_id, scan_job_id, metadata)
        VALUES (CAST(${eventId} AS uuid), ${actorType}, ${actorSubject},
                ${ownerSubject}, ${action}, ${outcome},
                CAST(${requestId} AS uuid), CAST(${scanId} AS uuid),
                CAST(${metadataJson} AS jsonb))`);
}

function loadScanResultsForActor(string id, string actorSubject, boolean admin)
        returns PersistedScanResult[]|error {
    postgresql:Client db = check getDatabaseClient();
    stream<PersistedScanResult, sql:Error?> resultStream =
        db->query(`
            SELECT address::text AS "address", port AS "port",
                   lower(state) AS "state"
              FROM scan_results
             WHERE scan_job_id = CAST(${id} AS uuid)
               AND EXISTS (
                   SELECT 1
                    FROM scan_jobs
                    WHERE scan_jobs.id = scan_results.scan_job_id
                      AND (${admin} OR scan_jobs.owner_subject = ${actorSubject})
               )
             ORDER BY address, port`);
    return check from PersistedScanResult result in resultStream
        select result;
}

function loadScanHistoryAfter(string ownerSubject, string cursorCreatedAt,
        string cursorId, int pageSize) returns PersistedScanHistoryItem[]|error {
    check validateHistoryLimit(pageSize);
    postgresql:Client db = check getDatabaseClient();
    stream<PersistedScanHistoryItem, sql:Error?> historyStream =
        db->query(`
            SELECT id::text AS "id", target AS "target",
                   start_port AS "startPort", end_port AS "endPort",
                   status AS "status",
                   to_char(created_at AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "createdAt",
                   to_char(updated_at AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "updatedAt"
              FROM scan_jobs
             WHERE owner_subject = ${ownerSubject}
               AND (created_at, id) <
                   (CAST(${cursorCreatedAt} AS timestamptz),
                    CAST(${cursorId} AS uuid))
             ORDER BY created_at DESC, id DESC
             LIMIT ${pageSize}`);
    return check from PersistedScanHistoryItem historyItem in historyStream
        select historyItem;
}

function validateHistoryLimit(int pageSize) returns error? {
    if pageSize < 1 || pageSize > 100 {
        return error("scan history limit must be between 1 and 100");
    }
}

function scanUpdateOutcome(sql:ExecutionResult result)
        returns ScanUpdateOutcome|error {
    int? affectedRows = result.affectedRowCount;
    if affectedRows is () {
        return error("database did not report an affected row count");
    }
    if affectedRows == 0 {
        return "UNCHANGED";
    }
    if affectedRows == 1 {
        return "APPLIED";
    }
    return error("database update affected an unexpected number of rows");
}

function requireAppliedUpdate(sql:ExecutionResult result, string message)
        returns error? {
    ScanUpdateOutcome outcome = check scanUpdateOutcome(result);
    if outcome == "UNCHANGED" {
        return error(message);
    }
}

function loadScanHistory(string ownerSubject, int pageSize)
        returns PersistedScanHistoryItem[]|error {
    check validateHistoryLimit(pageSize);
    postgresql:Client db = check getDatabaseClient();
    stream<PersistedScanHistoryItem, sql:Error?> historyStream =
        db->query(`
            SELECT id::text AS "id", target AS "target",
                   start_port AS "startPort", end_port AS "endPort",
                   status AS "status",
                   to_char(created_at AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "createdAt",
                   to_char(updated_at AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "updatedAt"
              FROM scan_jobs
             WHERE owner_subject = ${ownerSubject}
             ORDER BY created_at DESC, id DESC
             LIMIT ${pageSize}`);
    return check from PersistedScanHistoryItem historyItem in historyStream
        select historyItem;
}

function getDatabaseClient() returns postgresql:Client|error {
    postgresql:Client? db = databaseClient;
    if db is () {
        return error("scan persistence is disabled");
    }
    return db;
}
