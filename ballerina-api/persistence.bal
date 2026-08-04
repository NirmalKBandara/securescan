import ballerina/sql;
import ballerinax/postgresql;
import ballerinax/postgresql.driver as _;

configurable boolean persistenceEnabled = true;
configurable string databaseHost = "localhost";
configurable int databasePort = 5432;
configurable string databaseName = "securescan_dev";
configurable string databaseUser = "securescan";
configurable string databasePassword = "securescan_dev_only";
configurable string developmentOwnerSubject = "development-user";

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

function insertQueuedScan(string id, CreateScanRequest request) returns error? {
    postgresql:Client db = check getDatabaseClient();
    string target = request.target.trim();
    _ = check db->execute(`
        INSERT INTO scan_jobs
            (id, owner_subject, target, start_port, end_port, status)
        VALUES (CAST(${id} AS uuid), ${developmentOwnerSubject}, ${target},
                ${request.startPort}, ${request.endPort}, 'QUEUED')`);
}

function markScanDispatched(string id, string scannerScanId)
        returns ScanUpdateOutcome|error {
    postgresql:Client db = check getDatabaseClient();
    sql:ExecutionResult update = check db->execute(`
        UPDATE scan_jobs
           SET scanner_scan_id = CAST(${scannerScanId} AS uuid),
               status = 'RUNNING', started_at = CURRENT_TIMESTAMP,
               updated_at = CURRENT_TIMESTAMP
         WHERE id = CAST(${id} AS uuid) AND status = 'QUEUED'`);
    return scanUpdateOutcome(update);
}

function markScanDispatchFailed(string id, string failureCode,
        boolean blocked) returns ScanUpdateOutcome|error {
    postgresql:Client db = check getDatabaseClient();
    string status = blocked ? "BLOCKED" : "FAILED";
    sql:ExecutionResult update = check db->execute(`
        UPDATE scan_jobs
           SET status = ${status}, failure_code = ${failureCode},
               finished_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE id = CAST(${id} AS uuid) AND status = 'QUEUED'`);
    return scanUpdateOutcome(update);
}

function loadScanJob(string id, string ownerSubject)
        returns PersistedScanJob|error? {
    postgresql:Client db = check getDatabaseClient();
    stream<PersistedScanJob, sql:Error?> rowStream =
        db->query(`
            SELECT id::text AS "id",
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
               AND owner_subject = ${ownerSubject}`);
    PersistedScanJob[] rows = check from PersistedScanJob row in rowStream
        select row;
    return rows.length() == 0 ? () : rows[0];
}

function synchronizeScanJob(PersistedScanJob job, ScannerStatusResponse scanner)
        returns error? {
    postgresql:Client db = check getDatabaseClient();
    if scanner.status == "accepted" || scanner.status == "running" {
        return;
    }
    if scanner.status == "failed" {
        sql:ExecutionResult update = check db->execute(`
            UPDATE scan_jobs
               SET status = 'FAILED', failure_code = 'SCANNER_FAILED',
                   finished_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
             WHERE id = CAST(${job.id} AS uuid) AND status IN ('QUEUED', 'RUNNING')`);
        _ = scanUpdateOutcome(update);
        return;
    }

    ScannerResult result = <ScannerResult>scanner.result;
    transaction {
        // Locking before writing makes concurrent completion retries serialize.
        // Once the first transaction commits, later retries see a terminal job
        // and cannot append or replace result rows.
        stream<LockedScanJob, sql:Error?> lockStream = db->query(`
            SELECT id::text AS "id"
              FROM scan_jobs
             WHERE id = CAST(${job.id} AS uuid)
               AND owner_subject = ${developmentOwnerSubject}
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
        }
        check commit;
    }
}

function loadScanResults(string id, string ownerSubject)
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
                      AND scan_jobs.owner_subject = ${ownerSubject}
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
        returns ScanUpdateOutcome {
    int? affectedRows = result.affectedRowCount;
    return affectedRows is int && affectedRows == 0 ? "UNCHANGED" : "APPLIED";
}

function requireAppliedUpdate(sql:ExecutionResult result, string message)
        returns error? {
    if scanUpdateOutcome(result) == "UNCHANGED" {
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
