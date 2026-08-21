import { describe, expect, it } from "vitest";
import {
  APP_ROLES,
  authorizePath,
  extractApplicationRoles,
  hasRole,
  isAppMember,
} from "./authorization";
import type { AuthSession } from "./session-values";

function session(roles: string[], clientKind: AuthSession["clientKind"] = "user"): AuthSession {
  return {
    accessToken: "access-token",
    clientKind,
    expiresAt: Date.now() + 60_000,
    idToken: "id-token",
    issuer: "https://localhost:9443/oauth2/token",
    name: "Alice",
    roles,
    subject: "alice-id",
  };
}

describe("application roles", () => {
  it("extracts only exact SecureScan roles from supported WSO2 claim shapes", () => {
    expect(extractApplicationRoles({
      groups: ["securescan-user", "unrelated"],
      "http://wso2.org/claims/role": "securescan-admin, everyone",
    })).toEqual(["securescan-admin", "securescan-user"]);
  });

  it("supports a configured custom role claim without accepting lookalikes", () => {
    expect(extractApplicationRoles({ app_roles: "securescan-user,SecureScan-admin" }, "app_roles"))
      .toEqual(["securescan-user"]);
  });

  it("recognizes members and explicit roles", () => {
    const user = session([APP_ROLES.user]);
    expect(isAppMember(user)).toBe(true);
    expect(hasRole(user, APP_ROLES.admin)).toBe(false);
  });
});

describe("protected route matrix", () => {
  const user = session([APP_ROLES.user]);
  const admin = session([APP_ROLES.admin], "admin");
  const outsider = session([]);

  it.each(["/dashboard", "/history", "/scans/new", "/scans/scan-id"])(
    "allows a SecureScan user to access %s",
    (path) => expect(authorizePath(path, user)).toBe("allowed"),
  );

  it("sends anonymous users to authentication", () => {
    expect(authorizePath("/dashboard", null)).toBe("unauthenticated");
  });

  it("forbids authenticated identities without an application role", () => {
    expect(authorizePath("/dashboard", outsider)).toBe("forbidden");
  });

  it("forbids ordinary users from administration", () => {
    expect(authorizePath("/admin", user)).toBe("forbidden");
  });

  it("allows administrators into administration and ordinary routes", () => {
    expect(authorizePath("/admin", admin)).toBe("allowed");
    expect(authorizePath("/history", admin)).toBe("allowed");
  });

  it("requires a privileged-client login before an admin-role user enters administration", () => {
    expect(authorizePath("/admin", session([APP_ROLES.admin]))).toBe("reauthenticate");
  });
});
