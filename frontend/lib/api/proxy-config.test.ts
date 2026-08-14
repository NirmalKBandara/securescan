import { describe, expect, it } from "vitest";
import { loadApiProxyConfig } from "./proxy-config";

describe("loadApiProxyConfig", () => {
  it("uses the API Manager Gateway by default", () => {
    expect(loadApiProxyConfig({
      API_MANAGER_GATEWAY_URL: "https://localhost:8243/securescan/v1/",
    })).toEqual({
      baseUrl: "https://localhost:8243/securescan/v1",
      mode: "gateway",
    });
  });

  it("keeps direct Ballerina access as an explicit development fallback", () => {
    expect(loadApiProxyConfig({
      BALLERINA_API_BASE_URL: "http://127.0.0.1:9090/",
      SECURESCAN_API_GATEWAY_SECRET: "0123456789abcdef0123456789abcdef",
      SECURESCAN_API_MODE: "direct",
    })).toEqual({
      baseUrl: "http://127.0.0.1:9090",
      gatewaySecret: "0123456789abcdef0123456789abcdef",
      mode: "direct",
    });
  });

  it("does not silently fall back to Ballerina in gateway mode", () => {
    expect(() => loadApiProxyConfig({
      BALLERINA_API_BASE_URL: "http://127.0.0.1:9090",
    })).toThrow("API_MANAGER_GATEWAY_URL is required");
  });

  it("rejects ambiguous or unsupported upstream URLs", () => {
    expect(() => loadApiProxyConfig({
      API_MANAGER_GATEWAY_URL: "https://user@example.test/api?token=secret",
    })).toThrow(
      "API_MANAGER_GATEWAY_URL must not include credentials, a query, or a fragment",
    );
    expect(() => loadApiProxyConfig({
      API_MANAGER_GATEWAY_URL: "file:///tmp/gateway",
    })).toThrow("API_MANAGER_GATEWAY_URL must use http or https");
  });
});
