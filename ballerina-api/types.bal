import ballerina/http;

public type SuccessResponse record {|
    boolean success;
    json data;
|};

public const string INVALID_TARGET = "INVALID_TARGET";
public const string INVALID_PORT_RANGE = "INVALID_PORT_RANGE";
public const string INVALID_SCAN_ID = "INVALID_SCAN_ID";
public const string INVALID_REQUEST = "INVALID_REQUEST";
public const string BLOCKED_TARGET = "BLOCKED_TARGET";
public const string SCAN_NOT_FOUND = "SCAN_NOT_FOUND";
public const string SCANNER_UNAVAILABLE = "SCANNER_UNAVAILABLE";
public const string PERSISTENCE_UNAVAILABLE = "PERSISTENCE_UNAVAILABLE";
public const string JOB_LIMIT_REACHED = "JOB_LIMIT_REACHED";
public const string INTERNAL_ERROR = "INTERNAL_ERROR";
public const string AUTHENTICATION_REQUIRED = "AUTHENTICATION_REQUIRED";
public const string FORBIDDEN = "FORBIDDEN";
public const string REQUEST_TOO_LARGE = "REQUEST_TOO_LARGE";
public const string ALLOWED_TARGET_EXISTS = "ALLOWED_TARGET_EXISTS";
public const string ALLOWED_TARGET_NOT_FOUND = "ALLOWED_TARGET_NOT_FOUND";

public type ApiError record {|
    string code;
    string message;
    string requestId;
    map<json> details?;
|};

public type ErrorResponse record {|
    boolean success;
    ApiError 'error;
|};

public type ResponseHeaders record {|
    @http:Header {name: "X-Request-ID"}
    string requestId;
|};

public type ThrottledResponseHeaders record {|
    @http:Header {name: "X-Request-ID"}
    string requestId;
    @http:Header {name: "Retry-After"}
    string retryAfter;
|};

public type HealthData record {|
    string status;
    string serviceName;
|};

public type HealthOk record {|
    *http:Ok;
    SuccessResponse body;
|};

public type CreateScanRequest record {|
    string target;
    int startPort;
    int endPort;
    boolean authorized;
|};

public type ScanJobStatus "queued"|"accepted"|"running"|"completed"|"failed"|"blocked";

public type ScanPortState "open"|"closed";

public type CreateScanData record {|
    string id;
    ScanJobStatus status;
    string target;
    int startPort;
    int endPort;
|};

public type ScanPortResult record {|
    string address;
    int port;
    ScanPortState state;
|};

public type ScanResultData record {|
    string target;
    int startPort;
    int endPort;
    ScanPortResult[] results;
    int durationNanos;
|};

public type ScanStatusData record {|
    string id;
    ScanJobStatus status;
    string target;
    int startPort;
    int endPort;
    string createdAt;
    string updatedAt;
    string? failureCode = ();
    ScanResultData? result = ();
|};

public type ScanHistoryItem record {|
    string id;
    ScanJobStatus status;
    string target;
    int startPort;
    int endPort;
    string createdAt;
    string updatedAt;
|};

public type ScanHistoryData record {|
    ScanHistoryItem[] items;
    int pageSize;
|};

public type AllowedTargetKind "HOSTNAME"|"IP"|"CIDR";

public type CreateAllowedTargetRequest record {|
    AllowedTargetKind targetKind;
    string target;
    int? startPort = ();
    int? endPort = ();
|};

public type AllowedTargetData record {|
    string id;
    AllowedTargetKind targetKind;
    string target;
    int? startPort = ();
    int? endPort = ();
    boolean enabled;
    string createdBySubject;
    string createdAt;
    string updatedAt;
|};

public type AllowedTargetListData record {|
    AllowedTargetData[] items;
    int pageSize;
|};

public type CreateScanAccepted record {|
    *http:Accepted;
    ResponseHeaders headers;
    SuccessResponse body;
|};

public type ScanStatusOk record {|
    *http:Ok;
    ResponseHeaders headers;
    SuccessResponse body;
|};

public type ScanHistoryOk record {|
    *http:Ok;
    ResponseHeaders headers;
    SuccessResponse body;
|};

public type AllowedTargetOk record {|
    *http:Ok;
    ResponseHeaders headers;
    SuccessResponse body;
|};

public type AllowedTargetCreated record {|
    *http:Created;
    ResponseHeaders headers;
    SuccessResponse body;
|};

public type AllowedTargetListOk record {|
    *http:Ok;
    ResponseHeaders headers;
    SuccessResponse body;
|};

public type TooManyRequestsError record {|
    *http:TooManyRequests;
    ThrottledResponseHeaders headers;
    ErrorResponse body;
|};

public type BadRequestError record {|
    *http:BadRequest;
    ResponseHeaders headers;
    ErrorResponse body;
|};

public type PayloadTooLargeError record {|
    *http:PayloadTooLarge;
    ResponseHeaders headers;
    ErrorResponse body;
|};

public type NotFoundError record {|
    *http:NotFound;
    ResponseHeaders headers;
    ErrorResponse body;
|};

public type ConflictError record {|
    *http:Conflict;
    ResponseHeaders headers;
    ErrorResponse body;
|};

public type UnauthorizedError record {|
    *http:Unauthorized;
    ResponseHeaders headers;
    ErrorResponse body;
|};

public type ForbiddenError record {|
    *http:Forbidden;
    ResponseHeaders headers;
    ErrorResponse body;
|};

public type ServiceUnavailableError record {|
    *http:ServiceUnavailable;
    ResponseHeaders headers;
    ErrorResponse body;
|};

public type InternalServerErrorResponse record {|
    *http:InternalServerError;
    ResponseHeaders headers;
    ErrorResponse body;
|};
