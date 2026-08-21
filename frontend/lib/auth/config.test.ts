import { describe, expect, it } from "vitest";
import { loadOidcConfig } from "./config-values";

const valid = {
  APP_BASE_URL: "http://localhost:3000",
  AUTH_SESSION_SECRET: "0123456789abcdef0123456789abcdef",
  OIDC_CLIENT_ID: "secure-scan-client",
  OIDC_CLIENT_SECRET: "development-secret",
  OIDC_ISSUER: "https://localhost:9443/oauth2/token/",
  OIDC_ADMIN_CLIENT_ID: "secure-scan-admin-client",
  OIDC_ADMIN_CLIENT_SECRET: "admin-development-secret",
};

describe("loadOidcConfig", () => {
  it("derives exact callback URLs and normalizes the issuer", () => {
    const config = loadOidcConfig(valid);

    expect(config.issuer.toString()).toBe(
      "https://localhost:9443/oauth2/token",
    );
    expect(config.redirectUri).toBe("http://localhost:3000/auth/callback");
    expect(config.postLogoutRedirectUri).toBe("http://localhost:3000/login");
    expect(config.roleClaim).toBe("groups");
    expect(config.clientKind).toBe("user");
    expect(config.scope).toBe("openid profile email securescan:scan");
  });

  it("loads a separate privileged client with all required admin scopes", () => {
    const config = loadOidcConfig(valid, "admin");

    expect(config.clientKind).toBe("admin");
    expect(config.clientId).toBe("secure-scan-admin-client");
    expect(config.clientSecret).toBe("admin-development-secret");
    expect(config.scope).toBe(
      "openid profile email securescan:scan securescan:admin",
    );
  });

  it("fails closed when privileged credentials or scope are incomplete", () => {
    expect(() => loadOidcConfig({ ...valid, OIDC_ADMIN_CLIENT_ID: "" }, "admin"))
      .toThrow("OIDC_ADMIN_CLIENT_ID is required");
    expect(() => loadOidcConfig({
      ...valid,
      OIDC_ADMIN_SCOPES: "openid securescan:scan",
    }, "admin")).toThrow("OIDC_ADMIN_SCOPES must include securescan:admin");
  });

  it("rejects administrator scope on the ordinary client", () => {
    expect(() => loadOidcConfig({
      ...valid,
      OIDC_SCOPES: "openid securescan:scan securescan:admin",
    })).toThrow("OIDC_SCOPES must not include securescan:admin");
  });

  it("accepts an explicit role claim name", () => {
    expect(loadOidcConfig({ ...valid, OIDC_ROLE_CLAIM: "app_roles" }).roleClaim)
      .toBe("app_roles");
  });

  it("accepts configured scopes and requires the API scope", () => {
    expect(loadOidcConfig({
      ...valid,
      OIDC_SCOPES: "openid email securescan:scan securescan:scan",
    }).scope).toBe("openid email securescan:scan");
    expect(() => loadOidcConfig({ ...valid, OIDC_SCOPES: "openid email" }))
      .toThrow("OIDC_SCOPES must include securescan:scan");
  });

  it.each(["APP_BASE_URL", "AUTH_SESSION_SECRET", "OIDC_CLIENT_ID", "OIDC_CLIENT_SECRET", "OIDC_ISSUER"])(
    "rejects a missing %s",
    (name) => {
      expect(() => loadOidcConfig({ ...valid, [name]: " " })).toThrow(
        `${name} is required`,
      );
    },
  );

  it.each(["AUTH_SESSION_SECRET", "OIDC_CLIENT_ID", "OIDC_CLIENT_SECRET"])(
    "rejects the example placeholder for %s",
    (name) => {
      expect(() => loadOidcConfig({
        ...valid,
        [name]: "replace-with-a-real-development-value-123456",
      })).toThrow(`${name} still contains an example placeholder`);
    },
  );

  it("rejects a short session secret", () => {
    expect(() => loadOidcConfig({ ...valid, AUTH_SESSION_SECRET: "too-short" }))
      .toThrow("AUTH_SESSION_SECRET must contain at least 32 characters");
  });

  it("rejects unsafe URL schemes and ambiguous public base paths", () => {
    expect(() =>
      loadOidcConfig({ ...valid, OIDC_ISSUER: "file:///tmp/issuer" }),
    ).toThrow("OIDC_ISSUER must use http or https");
    expect(() =>
      loadOidcConfig({ ...valid, APP_BASE_URL: "http://localhost:3000/app" }),
    ).toThrow("APP_BASE_URL must not include a path");
  });
});
