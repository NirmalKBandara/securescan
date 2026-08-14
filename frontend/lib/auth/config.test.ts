import { describe, expect, it } from "vitest";
import { loadOidcConfig } from "./config";

const valid = {
  APP_BASE_URL: "http://localhost:3000",
  OIDC_CLIENT_ID: "secure-scan-client",
  OIDC_CLIENT_SECRET: "development-secret",
  OIDC_ISSUER: "https://localhost:9443/oauth2/token/",
};

describe("loadOidcConfig", () => {
  it("derives exact callback URLs and normalizes the issuer", () => {
    const config = loadOidcConfig(valid);

    expect(config.issuer.toString()).toBe(
      "https://localhost:9443/oauth2/token",
    );
    expect(config.redirectUri).toBe("http://localhost:3000/auth/callback");
    expect(config.postLogoutRedirectUri).toBe("http://localhost:3000/login");
    expect(config.scope).toBe("openid profile email");
  });

  it.each(["APP_BASE_URL", "OIDC_CLIENT_ID", "OIDC_CLIENT_SECRET", "OIDC_ISSUER"])(
    "rejects a missing %s",
    (name) => {
      expect(() => loadOidcConfig({ ...valid, [name]: " " })).toThrow(
        `${name} is required`,
      );
    },
  );

  it("rejects unsafe URL schemes and ambiguous public base paths", () => {
    expect(() =>
      loadOidcConfig({ ...valid, OIDC_ISSUER: "file:///tmp/issuer" }),
    ).toThrow("OIDC_ISSUER must use http or https");
    expect(() =>
      loadOidcConfig({ ...valid, APP_BASE_URL: "http://localhost:3000/app" }),
    ).toThrow("APP_BASE_URL must not include a path");
  });
});
