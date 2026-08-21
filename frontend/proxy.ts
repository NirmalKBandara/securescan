import { NextRequest, NextResponse } from "next/server";
import { authorizePath } from "@/lib/auth/authorization";
import { loadOidcConfig } from "@/lib/auth/config-values";
import { safeReturnTo } from "@/lib/auth/return-to";
import { readSession } from "@/lib/auth/session-values";

const SESSION_COOKIE = "securescan_session";

export function proxy(request: NextRequest) {
  const config = loadOidcConfig();
  const session = readSession(
    request.cookies.get(SESSION_COOKIE)?.value,
    config.sessionSecret,
  );
  const decision = authorizePath(request.nextUrl.pathname, session);

  if (decision === "allowed") return NextResponse.next();
  if (decision === "forbidden") {
    return NextResponse.redirect(new URL("/forbidden", request.url));
  }

  const returnTo = safeReturnTo(`${request.nextUrl.pathname}${request.nextUrl.search}`);
  const login = new URL("/login", request.url);
  login.searchParams.set("returnTo", returnTo);
  const response = NextResponse.redirect(login);
  if (decision !== "reauthenticate" && request.cookies.has(SESSION_COOKIE)) {
    response.cookies.set(SESSION_COOKIE, "", {
      httpOnly: true,
      maxAge: 0,
      path: "/",
      sameSite: "lax",
      secure: config.appBaseUrl.protocol === "https:",
    });
  }
  return response;
}

export const config = {
  matcher: ["/admin/:path*", "/dashboard/:path*", "/history/:path*", "/scans/:path*"],
};
