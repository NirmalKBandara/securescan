import ballerina/jballerina.java;
import ballerina/jballerina.java.arrays;
import ballerina/lang.'string;

// This bypass exists only so the isolated Ballerina HTTP contract suite can
// run without PostgreSQL. Startup validation binds it to the fixed test
// service and mock scanner; it is not a deployable authorization switch.
configurable boolean targetAuthorizationTestBypass = false;

type AuthorizedScanTarget record {|
    string allowedTargetId;
    string normalizedTarget;
    string[] resolvedAddresses;
|};

type TargetAuthorizationFailure record {|
    string code;
    string? allowedTargetId = ();
|};

function authorizeScanTarget(string ownerSubject, CreateScanRequest request)
        returns AuthorizedScanTarget|TargetAuthorizationFailure|error {
    string target = request.target.trim();
    NetworkTargetAuthorization networkAuthorization =
        check loadNetworkTargetAuthorization(target, ownerSubject,
            request.startPort, request.endPort);
    if networkAuthorization.inputIsAddress {
        string? allowedTargetId = networkAuthorization.allowedTargetId;
        if allowedTargetId is () {
            return {code: BLOCKED_TARGET};
        }
        if !allAddressesSafe([target]) {
            return {code: BLOCKED_TARGET, allowedTargetId: allowedTargetId};
        }
        return {
            allowedTargetId: allowedTargetId,
            normalizedTarget: target,
            resolvedAddresses: [target]
        };
    }

    string hostname = 'string:toLowerAscii(target);
    if !validExactHostname(hostname) {
        return {code: BLOCKED_TARGET};
    }
    string? allowedTargetId = check loadHostnameAllowedTarget(hostname,
            ownerSubject, request.startPort, request.endPort);
    if allowedTargetId is () {
        // Authorization is checked before DNS to avoid resolving attacker-selected
        // names that are not explicitly present in the allowlist.
        return {code: BLOCKED_TARGET};
    }
    string[]|error resolved = resolveAllAddresses(hostname);
    if resolved is error || !targetPassesAuthorization(allowedTargetId, resolved) {
        return {code: BLOCKED_TARGET, allowedTargetId: allowedTargetId};
    }
    return {
        allowedTargetId: allowedTargetId,
        normalizedTarget: hostname,
        resolvedAddresses: resolved
    };
}

function targetPassesAuthorization(string? allowedTargetId,
        string[] resolvedAddresses) returns boolean {
    return allowedTargetId is string && allAddressesSafe(resolvedAddresses);
}

function resolveAllAddresses(string hostname) returns string[]|error {
    handle|error answer = javaGetAllByName(java:fromString(hostname));
    if answer is error {
        return error("DNS resolution failed", answer);
    }
    int length = arrays:getLength(answer);
    string[] addresses = [];
    foreach int index in 0 ..< length {
        handle address = arrays:get(answer, index);
        string? possibleValue = java:toString(javaGetHostAddress(address));
        if possibleValue is () {
            return error("DNS resolution returned an invalid address");
        }
        string value = possibleValue;
        if !containsAddress(addresses, value) {
            addresses.push(value);
        }
    }
    return addresses;
}

function containsAddress(string[] addresses, string candidate) returns boolean {
    foreach string address in addresses {
        if address == candidate {
            return true;
        }
    }
    return false;
}

function allAddressesSafe(string[] addresses) returns boolean {
    if addresses.length() == 0 {
        return false;
    }
    foreach string address in addresses {
        if !addressIsSafe(address) {
            return false;
        }
    }
    return true;
}

function addressIsSafe(string address) returns boolean {
    handle|error parsed = javaGetByName(java:fromString(address));
    if parsed is error {
        return false;
    }
    if javaIsAnyLocalAddress(parsed) || javaIsLoopbackAddress(parsed) ||
            javaIsLinkLocalAddress(parsed) || javaIsSiteLocalAddress(parsed) ||
            javaIsMulticastAddress(parsed) {
        return false;
    }
    string? possibleNormalized = java:toString(javaGetHostAddress(parsed));
    if possibleNormalized is () {
        return false;
    }
    string normalized = 'string:toLowerAscii(possibleNormalized);
    // Java does not classify IPv6 unique-local addresses (fc00::/7) as
    // site-local. Treat them as private explicitly. Metadata endpoints are
    // listed explicitly as defense in depth even though they fall in blocked
    // link-local/private ranges.
    return !(normalized.startsWith("fc") || normalized.startsWith("fd") ||
        normalized == "169.254.169.254" || normalized == "fd00:ec2::254");
}

function validateTargetAuthorizationConfiguration() returns error? {
    if targetAuthorizationTestBypass && (persistenceEnabled ||
            serviceName != "securescan-api-test" ||
            scannerServiceUrl != "http://localhost:18081") {
        return error("target authorization bypass is restricted to isolated tests");
    }
    if !persistenceEnabled && !targetAuthorizationTestBypass {
        return error("target authorization requires persistence");
    }
}

function javaGetAllByName(handle hostname) returns handle|error = @java:Method {
    name: "getAllByName",
    'class: "java.net.InetAddress",
    paramTypes: ["java.lang.String"]
} external;

function javaGetByName(handle address) returns handle|error = @java:Method {
    name: "getByName",
    'class: "java.net.InetAddress",
    paramTypes: ["java.lang.String"]
} external;

function javaGetHostAddress(handle receiver) returns handle = @java:Method {
    name: "getHostAddress",
    'class: "java.net.InetAddress"
} external;

function javaIsAnyLocalAddress(handle receiver) returns boolean = @java:Method {
    name: "isAnyLocalAddress",
    'class: "java.net.InetAddress"
} external;

function javaIsLoopbackAddress(handle receiver) returns boolean = @java:Method {
    name: "isLoopbackAddress",
    'class: "java.net.InetAddress"
} external;

function javaIsLinkLocalAddress(handle receiver) returns boolean = @java:Method {
    name: "isLinkLocalAddress",
    'class: "java.net.InetAddress"
} external;

function javaIsSiteLocalAddress(handle receiver) returns boolean = @java:Method {
    name: "isSiteLocalAddress",
    'class: "java.net.InetAddress"
} external;

function javaIsMulticastAddress(handle receiver) returns boolean = @java:Method {
    name: "isMulticastAddress",
    'class: "java.net.InetAddress"
} external;
