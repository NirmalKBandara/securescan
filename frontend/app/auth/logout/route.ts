import { NextRequest, NextResponse } from "next/server";
import { loadOidcConfig } from "@/lib/auth/config";
import { client, getOidcConfiguration } from "@/lib/auth/oidc";
import { clearAuthCookies, readSession, SESSION_COOKIE } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  const config = loadOidcConfig();
  const session = readSession(
    request.cookies.get(SESSION_COOKIE)?.value,
    config.sessionSecret,
  );
  let destination = new URL(config.postLogoutRedirectUri);

  if (session) {
    try {
      const oidc = await getOidcConfiguration();
      destination = client.buildEndSessionUrl(oidc, {
        id_token_hint: session.idToken,
        post_logout_redirect_uri: config.postLogoutRedirectUri,
      });
    } catch {
      // Local logout still succeeds when the development identity server is down.
    }
  }

  const response = NextResponse.redirect(destination, 303);
  response.headers.set("Cache-Control", "no-store");
  clearAuthCookies(response, config);
  return response;
}
