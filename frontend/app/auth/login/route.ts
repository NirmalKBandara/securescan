import { NextRequest, NextResponse } from "next/server";
import { loadOidcConfig } from "@/lib/auth/config";
import { client, getOidcConfiguration } from "@/lib/auth/oidc";
import { isAdminReturnTo, safeReturnTo } from "@/lib/auth/return-to";
import { setTransactionCookie } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const returnTo = safeReturnTo(request.nextUrl.searchParams.get("returnTo"));
    const clientKind = isAdminReturnTo(returnTo) ? "admin" : "user";
    const config = loadOidcConfig(process.env, clientKind);
    const oidc = await getOidcConfiguration(clientKind);
    if (!oidc.serverMetadata().supportsPKCE("S256")) {
      throw new Error("The identity provider does not advertise PKCE S256");
    }

    const codeVerifier = client.randomPKCECodeVerifier();
    const state = client.randomState();
    const nonce = client.randomNonce();
    const codeChallenge = await client.calculatePKCECodeChallenge(codeVerifier);
    const destination = client.buildAuthorizationUrl(oidc, {
      client_id: config.clientId,
      code_challenge: codeChallenge,
      code_challenge_method: "S256",
      nonce,
      redirect_uri: config.redirectUri,
      response_type: "code",
      scope: config.scope,
      state,
    });

    const response = NextResponse.redirect(destination);
    response.headers.set("Cache-Control", "no-store");
    setTransactionCookie(response, {
      clientKind,
      codeVerifier,
      expiresAt: Date.now() + 10 * 60 * 1000,
      nonce,
      returnTo,
      state,
    }, config);
    return response;
  } catch {
    return NextResponse.redirect(new URL("/login?error=identity_unavailable", request.url));
  }
}
