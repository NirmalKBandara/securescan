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

function insertQueuedScan(string id, CreateScanRequest request) returns error? {
    postgresql:Client db = check getDatabaseClient();
    string target = request.target.trim();
    _ = check db->execute(`
        INSERT INTO scan_jobs
            (id, owner_subject, target, start_port, end_port, status)
        VALUES (CAST(${id} AS uuid), ${developmentOwnerSubject}, ${target},
                ${request.startPort}, ${request.endPort}, 'QUEUED')`);
}

function markScanDispatched(string id, string scannerScanId) returns error? {
    postgresql:Client db = check getDatabaseClient();
    _ = check db->execute(`
        UPDATE scan_jobs
           SET scanner_scan_id = CAST(${scannerScanId} AS uuid),
               status = 'RUNNING', started_at = CURRENT_TIMESTAMP,
               updated_at = CURRENT_TIMESTAMP
         WHERE id = CAST(${id} AS uuid) AND status = 'QUEUED'`);
}

function markScanDispatchFailed(string id, string failureCode,
        boolean blocked) returns error? {
    postgresql:Client db = check getDatabaseClient();
    string status = blocked ? "BLOCKED" : "FAILED";
    _ = check db->execute(`
        UPDATE scan_jobs
           SET status = ${status}, failure_code = ${failureCode},
               finished_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE id = CAST(${id} AS uuid) AND status = 'QUEUED'`);
}

function loadScanJob(string id) returns PersistedScanJob|error? {
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
             WHERE id = CAST(${id} AS uuid)`);
    PersistedScanJob[] rows = check from PersistedScanJob row in rowStream
        select row;
    return rows.length() == 0 ? () : rows[0];
}

function synchronizeScanJob(PersistedScanJob job, ScannerStatusResponse scanner)
        returns error? {
    postgresql:Client db = check getDatabaseClient();
    if scanner.status == "accepted" || scanner.status == "running" {
        _ = check db->execute(`
            UPDATE scan_jobs
               SET status = 'RUNNING', updated_at = CURRENT_TIMESTAMP
             WHERE id = CAST(${job.id} AS uuid) AND status IN ('QUEUED', 'RUNNING')`);
        return;
    }
    if scanner.status == "failed" {
        _ = check db->execute(`
            UPDATE scan_jobs
               SET status = 'FAILED', failure_code = 'SCANNER_FAILED',
                   finished_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
             WHERE id = CAST(${job.id} AS uuid) AND status IN ('QUEUED', 'RUNNING')`);
        return;
    }

    ScannerResult result = <ScannerResult>scanner.result;
    // Result writes are idempotent. The job is made terminal only after every
    // observation is stored, so an interrupted poll can safely retry.
    foreach ScannerPortResult port in result.results {
        _ = check db->execute(`
            INSERT INTO scan_results
                (scan_job_id, address, port, state, observed_at)
            VALUES (CAST(${job.id} AS uuid), CAST(${port.address} AS inet),
                    ${port.port}, upper(${port.state}), CURRENT_TIMESTAMP)
            ON CONFLICT (scan_job_id, address, port)
            DO UPDATE SET state = EXCLUDED.state,
                          observed_at = EXCLUDED.observed_at`);
    }
    _ = check db->execute(`
        UPDATE scan_jobs
           SET status = 'COMPLETED', duration_nanos = ${result.duration},
               finished_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE id = CAST(${job.id} AS uuid) AND status IN ('QUEUED', 'RUNNING')`);
}

function loadScanResults(string id) returns PersistedScanResult[]|error {
    postgresql:Client db = check getDatabaseClient();
    stream<PersistedScanResult, sql:Error?> resultStream =
        db->query(`
            SELECT address::text AS "address", port AS "port",
                   lower(state) AS "state"
              FROM scan_results
             WHERE scan_job_id = CAST(${id} AS uuid)
             ORDER BY address, port`);
    return check from PersistedScanResult result in resultStream
        select result;
}

function getDatabaseClient() returns postgresql:Client|error {
    postgresql:Client? db = databaseClient;
    if db is () {
        return error("scan persistence is disabled");
    }
    return db;
}
