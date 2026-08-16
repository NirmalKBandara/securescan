import ballerina/test;

@test:Config
function testAuthorizedAddressSetHasHardCap() {
    string[] addresses = [
        "8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1",
        "9.9.9.9", "149.112.112.112", "208.67.222.222", "208.67.220.220",
        "64.6.64.6", "64.6.65.6", "84.200.69.80", "84.200.70.40",
        "94.140.14.14", "94.140.15.15", "76.76.2.0", "76.76.10.0",
        "185.228.168.9"
    ];
    test:assertFalse(allAddressesSafe(addresses),
            msg = "authorization must cap total address-by-port work");
}
