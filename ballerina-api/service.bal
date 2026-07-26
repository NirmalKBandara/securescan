import ballerina/http;

configurable int listenerPort = 9090;
configurable string serviceName = "securescan-api";

// Resource below becomes GET /health.
service / on new http:Listener(listenerPort) {

    resource function get health() returns HealthOk {
        HealthData healthData = {
            status: "ok",
            serviceName: serviceName
        };

        // Serializes this typed record as JSON.
        return {
            body: {
                success: true,
                data: healthData
            }
        };
    }
}
