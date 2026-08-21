export interface OidcConfig {
  appBaseUrl: URL;
  clientKind: OidcClientKind;
  clientId: string;
  clientSecret: string;
  issuer: URL;
  postLogoutRedirectUri: string;
  redirectUri: string;
  roleClaim: string;
  scope: string;
  sessionSecret: string;
}

export type OidcClientKind = "user" | "admin";

const DEFAULT_USER_SCOPES = "openid profile email securescan:scan";
const DEFAULT_ADMIN_SCOPES = "openid profile email securescan:scan securescan:admin";

function oidcScopes(
  name: string,
  value: string | undefined,
  defaultScopes: string,
  requiredScopes: string[],
) {
  const scopes = (value?.trim() || defaultScopes).split(/\s+/);
  const uniqueScopes = [...new Set(scopes)];
  for (const requiredScope of requiredScopes) {
    if (!uniqueScopes.includes(requiredScope)) {
      throw new Error(`${name} must include ${requiredScope}`);
    }
  }
  return uniqueScopes.join(" ");
}

function required(name: string, value: string | undefined) {
  const candidate = value?.trim();
  if (!candidate) throw new Error(`${name} is required`);
  return candidate;
}

function requiredCredential(name: string, value: string | undefined) {
  const candidate = required(name, value);
  if (/^(replace-with|change-me|changeme)/i.test(candidate)) {
    throw new Error(`${name} still contains an example placeholder`);
  }
  return candidate;
}

function absoluteHttpUrl(name: string, value: string | undefined) {
  const candidate = required(name, value);
  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    throw new Error(`${name} must be a valid absolute URL`);
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`${name} must use http or https`);
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error(`${name} must not include credentials, a query, or a fragment`);
  }

  url.pathname = url.pathname.replace(/\/$/, "");
  return url;
}

export function loadOidcConfig(
  source: Record<string, string | undefined> = process.env,
  clientKind: OidcClientKind = "user",
): OidcConfig {
  const appBaseUrl = absoluteHttpUrl("APP_BASE_URL", source.APP_BASE_URL);
  if (appBaseUrl.pathname !== "/") {
    throw new Error("APP_BASE_URL must not include a path");
  }

  const issuer = absoluteHttpUrl("OIDC_ISSUER", source.OIDC_ISSUER);
  const sessionSecret = requiredCredential(
    "AUTH_SESSION_SECRET",
    source.AUTH_SESSION_SECRET,
  );
  if (sessionSecret.length < 32) {
    throw new Error("AUTH_SESSION_SECRET must contain at least 32 characters");
  }

  const admin = clientKind === "admin";
  const clientIdName = admin ? "OIDC_ADMIN_CLIENT_ID" : "OIDC_CLIENT_ID";
  const clientSecretName = admin ? "OIDC_ADMIN_CLIENT_SECRET" : "OIDC_CLIENT_SECRET";
  const scopeName = admin ? "OIDC_ADMIN_SCOPES" : "OIDC_SCOPES";
  const scope = oidcScopes(
    scopeName,
    source[scopeName],
    admin ? DEFAULT_ADMIN_SCOPES : DEFAULT_USER_SCOPES,
    admin
      ? ["openid", "securescan:scan", "securescan:admin"]
      : ["openid", "securescan:scan"],
  );
  if (!admin && scope.split(" ").includes("securescan:admin")) {
    throw new Error("OIDC_SCOPES must not include securescan:admin");
  }

  return Object.freeze({
    appBaseUrl,
    clientKind,
    clientId: requiredCredential(clientIdName, source[clientIdName]),
    clientSecret: requiredCredential(clientSecretName, source[clientSecretName]),
    issuer,
    postLogoutRedirectUri: new URL("/login", appBaseUrl).toString(),
    redirectUri: new URL("/auth/callback", appBaseUrl).toString(),
    roleClaim: source.OIDC_ROLE_CLAIM?.trim() || "groups",
    scope,
    sessionSecret,
  });
}
