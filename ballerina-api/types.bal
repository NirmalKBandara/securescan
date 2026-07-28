import ballerina/http;

// Common success envelope for public API responses.
public type SuccessResponse record {|
    boolean success;
    json data;
|};

// Stable public error codes used by clients and tests.
public const string INVALID_TARGET = "INVALID_TARGET";
public const string INVALID_PORT_RANGE = "INVALID_PORT_RANGE";
public const string BLOCKED_TARGET = "BLOCKED_TARGET";
public const string SCANNER_UNAVAILABLE = "SCANNER_UNAVAILABLE";
public const string INTERNAL_ERROR = "INTERNAL_ERROR";

// Safe client-facing error object.
public type ApiError record {|
    string code;
    string message;
    map<json> details?;
|};

// Common error envelope for all public API errors.
public type ErrorResponse record {|
    boolean success;
    ApiError 'error;
|};

// GET /health response data.
public type HealthData record {|
    string status;
    string serviceName;
|};

// GET /health 200 response.
public type HealthOk record {|
    *http:Ok;
    SuccessResponse body;
|};

// Public scan creation request.
public type CreateScanRequest record {|
    string target;
    int startPort;
    int endPort;
    boolean authorized;
|};

// Public scan creation response data.
public type CreateScanData record {|
    string id;
    string status;
    string target;
    int startPort;
    int endPort;
|};

// POST /api/v1/scans success response.
public type CreateScanAccepted record {|
    *http:Accepted;
    SuccessResponse body;
|};

// 400 response for validation failures.
public type BadRequestError record {|
    *http:BadRequest;
    ErrorResponse body;
|};

// Safe fallback for unexpected downstream.
public type InternalServerErrorResponse record {|
    *http:InternalServerError;
    ErrorResponse body;
|};
