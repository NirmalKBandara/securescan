import ballerina/http;

configurable boolean authenticationEnabled = true;
configurable string gatewaySharedSecret = "";
configurable string developmentOwnerSubject = "development-user";

const string SUBJECT_HEADER = "X-SecureScan-Subject";
const string ROLES_HEADER = "X-SecureScan-Roles";
const string GATEWAY_SECRET_HEADER = "X-SecureScan-Gateway-Secret";
const string USER_ROLE = "securescan-user";
const string ADMIN_ROLE = "securescan-admin";

type AuthContext record {|
    string subject;
    boolean admin;
|};

function validateAuthenticationConfiguration() returns error? {
    if authenticationEnabled && gatewaySharedSecret.length() < 32 {
        return error("gatewaySharedSecret must contain at least 32 characters when authentication is enabled");
    }
}

function authenticateRequest(http:Request request, string requestId)
        returns AuthContext|UnauthorizedError|ForbiddenError {
    if !authenticationEnabled {
        return {subject: developmentOwnerSubject, admin: true};
    }

    string|http:HeaderNotFoundError suppliedSecret =
        request.getHeader(GATEWAY_SECRET_HEADER);
    string|http:HeaderNotFoundError suppliedSubject = request.getHeader(SUBJECT_HEADER);
    string|http:HeaderNotFoundError suppliedRoles = request.getHeader(ROLES_HEADER);
    if suppliedSecret is http:HeaderNotFoundError ||
            suppliedSubject is http:HeaderNotFoundError ||
            suppliedRoles is http:HeaderNotFoundError {
        return authenticationRequired(requestId);
    }

    return authenticateGatewayIdentity(suppliedSecret, suppliedSubject,
            suppliedRoles, gatewaySharedSecret, requestId);
}

function authenticateGatewayIdentity(string suppliedSecret, string suppliedSubject,
        string suppliedRoles, string expectedSecret, string requestId)
        returns AuthContext|UnauthorizedError|ForbiddenError {
    if suppliedSecret != expectedSecret {
        return authenticationRequired(requestId);
    }

    string subject = suppliedSubject.trim();
    if subject.length() < 1 || subject.length() > 255 {
        return authenticationRequired(requestId);
    }

    boolean user = false;
    boolean admin = false;
    foreach string rawRole in re `,`.split(suppliedRoles) {
        string role = rawRole.trim();
        user = user || role == USER_ROLE;
        admin = admin || role == ADMIN_ROLE;
    }
    if !user && !admin {
        return forbidden(requestId);
    }
    return {subject: subject, admin: admin};
}

function canAccessOwner(AuthContext context, string ownerSubject) returns boolean {
    return context.admin || context.subject == ownerSubject;
}

function requireAdmin(AuthContext context, string requestId) returns ForbiddenError? {
    return context.admin ? () : forbidden(requestId);
}

function authenticationRequired(string requestId) returns UnauthorizedError {
    return {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: AUTHENTICATION_REQUIRED,
                message: "Valid gateway authentication is required",
                requestId: requestId
            }
        }
    };
}

function forbidden(string requestId) returns ForbiddenError {
    return {
        headers: {requestId: requestId},
        body: {
            success: false,
            'error: {
                code: FORBIDDEN,
                message: "The authenticated identity is not authorized for this operation",
                requestId: requestId
            }
        }
    };
}
