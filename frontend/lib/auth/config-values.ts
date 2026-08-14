export interface OidcConfig {
  appBaseUrl: URL;
  clientId: string;
  clientSecret: string;
  issuer: URL;
  postLogoutRedirectUri: string;
  redirectUri: string;
  roleClaim: string;
  scope: string;
  sessionSecret: string;
}

function required(name: string, value: string | undefined) {
  const candidate = value?.trim();
  if (!candidate) throw new Error(`${name} is required`);
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
): OidcConfig {
  const appBaseUrl = absoluteHttpUrl("APP_BASE_URL", source.APP_BASE_URL);
  if (appBaseUrl.pathname !== "/") {
    throw new Error("APP_BASE_URL must not include a path");
  }

  const issuer = absoluteHttpUrl("OIDC_ISSUER", source.OIDC_ISSUER);
  const sessionSecret = required("AUTH_SESSION_SECRET", source.AUTH_SESSION_SECRET);
  if (sessionSecret.length < 32) {
    throw new Error("AUTH_SESSION_SECRET must contain at least 32 characters");
  }

  return Object.freeze({
    appBaseUrl,
    clientId: required("OIDC_CLIENT_ID", source.OIDC_CLIENT_ID),
    clientSecret: required("OIDC_CLIENT_SECRET", source.OIDC_CLIENT_SECRET),
    issuer,
    postLogoutRedirectUri: new URL("/login", appBaseUrl).toString(),
    redirectUri: new URL("/auth/callback", appBaseUrl).toString(),
    roleClaim: source.OIDC_ROLE_CLAIM?.trim() || "groups",
    scope: "openid profile email",
    sessionSecret,
  });
}
