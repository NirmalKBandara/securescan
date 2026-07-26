import ballerina/http;

// The common envelope for successful public API responses.
public type SuccessResponse record {|
    boolean success;
    json data;
|};

// ApiError contains safe, client-facing error information.

// `code` : intended for application logic, for example: INVALID_TARGET, BLOCKED_TARGET, or INTERNAL_ERROR.
// `message` : human-readable explanation.
// `details` : optional and can later hold safe validation information.

public type ApiError record {|
    string code;
    string message;
    map<json> details?;
|};

// The common envelope for all public API errors.

// Ex:
// {
//   "success": false,
//   "errorName": {
//     "code": "INVALID_TARGET",
//     "message": "The supplied target is invalid"
//   }
// }

public type ErrorResponse record {|
    boolean success;
    ApiError errorName;
|};

// The endpoint-specific data returned by GET /health.
public type HealthData record {|
    string status;
    string serviceName;
|};

// HealthOk explicitly connects the response body with HTTP 200 OK.
public type HealthOk record {|
    *http:Ok;
    SuccessResponse body;
|};
