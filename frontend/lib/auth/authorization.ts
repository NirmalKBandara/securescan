import type { AuthSession } from "./session-values";

export const APP_ROLES = Object.freeze({
  admin: "securescan-admin",
  user: "securescan-user",
} as const);

export type AppRole = (typeof APP_ROLES)[keyof typeof APP_ROLES];
export type AccessDecision = "allowed" | "forbidden" | "reauthenticate" | "unauthenticated";

function claimValues(value: unknown) {
  if (Array.isArray(value)) return value.filter((entry): entry is string => typeof entry === "string");
  if (typeof value === "string") return value.split(",");
  return [];
}

export function extractApplicationRoles(
  claims: Record<string, unknown>,
  configuredClaim = "groups",
) {
  const values = [
    ...claimValues(claims[configuredClaim]),
    ...claimValues(claims.groups),
    ...claimValues(claims.roles),
    ...claimValues(claims.role),
    ...claimValues(claims["http://wso2.org/claims/role"]),
  ].map((role) => role.trim());

  return [...new Set(values)]
    .filter((role): role is AppRole => role === APP_ROLES.user || role === APP_ROLES.admin)
    .sort();
}

export function hasRole(session: AuthSession | null, role: AppRole) {
  return Boolean(session?.roles.includes(role));
}

export function isAppMember(session: AuthSession | null) {
  return hasRole(session, APP_ROLES.user) || hasRole(session, APP_ROLES.admin);
}

export function authorizePath(
  pathname: string,
  session: AuthSession | null,
): AccessDecision {
  if (!session) return "unauthenticated";
  if (!isAppMember(session)) return "forbidden";
  if (pathname === "/admin" || pathname.startsWith("/admin/")) {
    if (!hasRole(session, APP_ROLES.admin)) return "forbidden";
    return session.clientKind === "admin" ? "allowed" : "reauthenticate";
  }
  return "allowed";
}
