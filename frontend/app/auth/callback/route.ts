import { NextRequest, NextResponse } from "next/server";
import { loadOidcConfig } from "@/lib/auth/config";
import { extractApplicationRoles } from "@/lib/auth/authorization";
import { client, getOidcConfiguration } from "@/lib/auth/oidc";
import {
  clearAuthCookies,
  readTransaction,
  setSessionCookie,
  TRANSACTION_COOKIE,
} from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const baseConfig = loadOidcConfig();
  const transaction = readTransaction(
    request.cookies.get(TRANSACTION_COOKIE)?.value,
    baseConfig.sessionSecret,
  );

  if (!transaction) {
    const response = NextResponse.redirect(new URL("/login?error=invalid_transaction", request.url));
    clearAuthCookies(response, baseConfig);
    return response;
  }

  try {
    const config = loadOidcConfig(process.env, transaction.clientKind);
    const oidc = await getOidcConfiguration(transaction.clientKind);
    const tokens = await client.authorizationCodeGrant(
      oidc,
      request.nextUrl,
      {
        expectedNonce: transaction.nonce,
        expectedState: transaction.state,
        pkceCodeVerifier: transaction.codeVerifier,
      },
      { redirect_uri: config.redirectUri },
    );
    const claims = tokens.claims();
    if (!claims?.sub || !claims.iss || !tokens.id_token || !tokens.access_token) {
      throw new Error("Validated token response is missing required identity data");
    }

    const now = Date.now();
    const tokenExpiry = typeof claims.exp === "number" ? claims.exp * 1000 : now + 60 * 60 * 1000;
    const expiresAt = Math.min(tokenExpiry, now + 8 * 60 * 60 * 1000);
    if (expiresAt <= now) throw new Error("Validated ID token is expired");

    const nameClaim = claims.name ?? claims.preferred_username ?? claims.email ?? claims.sub;
    const response = NextResponse.redirect(new URL(transaction.returnTo, config.appBaseUrl), 303);
    response.headers.set("Cache-Control", "no-store");
    setSessionCookie(response, {
      accessToken: tokens.access_token,
      clientKind: transaction.clientKind,
      email: typeof claims.email === "string" ? claims.email : undefined,
      expiresAt,
      idToken: tokens.id_token,
      issuer: claims.iss,
      name: typeof nameClaim === "string" ? nameClaim : claims.sub,
      roles: extractApplicationRoles(claims as Record<string, unknown>, config.roleClaim),
      subject: claims.sub,
    }, config);
    response.cookies.set(TRANSACTION_COOKIE, "", {
      httpOnly: true,
      maxAge: 0,
      path: "/",
      sameSite: "lax",
      secure: config.appBaseUrl.protocol === "https:",
    });
    return response;
  } catch {
    const response = NextResponse.redirect(new URL("/login?error=authentication_failed", request.url));
    clearAuthCookies(response, baseConfig);
    return response;
  }
}
