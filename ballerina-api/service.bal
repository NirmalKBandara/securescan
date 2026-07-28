import ballerina/http;

configurable int listenerPort = 9090;
configurable string serviceName = "securescan-api";

// Public SecureScan API service.
service / on new http:Listener(listenerPort) {

    resource function get health() returns HealthOk {
        HealthData healthData = {
            status: "ok",
            serviceName: serviceName
        };

        return {
            body: {
                success: true,
                data: healthData
            }
        };
    }

    // Validate and bind the public API contract only.
    resource function post api/v1/scans(@http:Payload CreateScanRequest request)
            returns CreateScanAccepted|BadRequestError|InternalServerErrorResponse {

        BadRequestError? validationError = validateCreateScanRequest(request);
        if validationError is BadRequestError {
            return validationError;
        }

        ScannerCreateResponse|error scannerResult = createScannerJob(request);

        // Never return the downstream error, URL, or body to the public client.
        if scannerResult is error {
            InternalServerErrorResponse internalError = {
                body: {
                    success: false,
                    'error: {
                        code: INTERNAL_ERROR,
                        message: "Unable to create the scan"
                    }
                }
            };
            return internalError;
        }

        CreateScanData scanData = {
            id: scannerResult.id,
            status: scannerResult.status,
            target: scannerResult.target,
            startPort: scannerResult.startPort,
            endPort: scannerResult.endPort
        };

        return {
            body: {
                success: true,
                data: scanData
            }
        };
    }
}

// Public request validation close to the API boundary.
function validateCreateScanRequest(CreateScanRequest request) returns BadRequestError? {
    string trimmedTarget = request.target.trim();

    if trimmedTarget == "" {
        return badRequest(
                INVALID_TARGET,
                "Target is required",
                {
                    "field": "target"
                }
        );
    }

    if request.startPort < 1 || request.startPort > 65535 {
        return badRequest(
                INVALID_PORT_RANGE,
                "Start port must be between 1 and 65535",
                {
                    "field": "startPort",
                    min: 1,
                    max: 65535
                }
        );
    }

    if request.endPort < 1 || request.endPort > 65535 {
        return badRequest(
                INVALID_PORT_RANGE,
                "End port must be between 1 and 65535",
                {
                    "field": "endPort",
                    min: 1,
                    max: 65535
                }
        );
    }

    if request.startPort > request.endPort {
        return badRequest(
                INVALID_PORT_RANGE,
                "Start port must be less than or equal to end port",
                {
                    startPort: request.startPort,
                    endPort: request.endPort
                }
        );
    }

    if !request.authorized {
        return badRequest(
                BLOCKED_TARGET,
                "Authorized-use confirmation is required before creating a scan",
                {
                    "field": "authorized"
                }
        );
    }

    return ();
}

// Builds one stable public 400 response.
function badRequest(string code, string message, map<json> details)
        returns BadRequestError {

    return {
        body: {
            success: false,
            'error: {
                code: code,
                message: message,
                details: details
            }
        }
    };
}
