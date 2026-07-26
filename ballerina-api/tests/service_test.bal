import ballerina/http;
import ballerina/test;

final http:Client healthClient = check new ("http://localhost:9091");

@test:Config {}
function testHealthEndpoint() returns error? {
    // HTTP GET request to the service.
    http:Response response = check healthClient->/health;

    // Verify that the endpoint returns the required status code.
    test:assertEquals(
            response.statusCode,
            http:STATUS_OK,
            msg = "GET /health must return HTTP 200"
    );

    json actualPayload = check response.getJsonPayload();

    json expectedPayload = {
        "success": true,
        "data": {
            "status": "ok",
            "serviceName": "securescan-api-test"
        }
    };

    // Verify the complete public response contract.
    test:assertEquals(
            actualPayload,
            expectedPayload,
            msg = "GET /health returned an unexpected JSON response"
    );
}
