import { describe, expect, it } from "vitest";
import { loadApiProxyConfig } from "./proxy-config";

describe("loadApiProxyConfig", () => {
  it("uses the API Manager Gateway by default", () => {
    expect(loadApiProxyConfig({
      API_MANAGER_GATEWAY_URL: "https://localhost:8243/securescan/v1/",
    })).toEqual({
      baseUrl: "https://localhost:8243/securescan/v1",
      maxRequestBytes: 4096,
      mode: "gateway",
      timeoutMs: 10000,
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
      maxRequestBytes: 4096,
      mode: "direct",
      timeoutMs: 10000,
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

  it("allows tighter limits but rejects settings that weaken the hard caps", () => {
    expect(loadApiProxyConfig({
      API_GATEWAY_TIMEOUT_MS: "5000",
      API_MANAGER_GATEWAY_URL: "https://localhost:8243/securescan/v1",
      API_MAX_REQUEST_BYTES: "2048",
    })).toMatchObject({ maxRequestBytes: 2048, timeoutMs: 5000 });
    expect(() => loadApiProxyConfig({
      API_MANAGER_GATEWAY_URL: "https://localhost:8243/securescan/v1",
      API_MAX_REQUEST_BYTES: "4097",
    })).toThrow("API_MAX_REQUEST_BYTES must be an integer between 1 and 4096");
    expect(() => loadApiProxyConfig({
      API_GATEWAY_TIMEOUT_MS: "10001",
      API_MANAGER_GATEWAY_URL: "https://localhost:8243/securescan/v1",
    })).toThrow("API_GATEWAY_TIMEOUT_MS must be an integer between 1 and 10000");
  });
});
