import "server-only";

import { cookies } from "next/headers";
import type { NextResponse } from "next/server";
import type { OidcConfig } from "./config";
import { loadOidcConfig } from "./config";
import { seal } from "./session-codec";
import {
  readSession,
  type AuthSession,
  type AuthTransaction,
} from "./session-values";

export { readSession, readTransaction } from "./session-values";
export type { AuthSession, AuthTransaction } from "./session-values";

export const SESSION_COOKIE = "securescan_session";
export const TRANSACTION_COOKIE = "securescan_oidc_transaction";

function cookieOptions(config: OidcConfig, maxAge: number) {
  return {
    httpOnly: true,
    maxAge,
    path: "/",
    sameSite: "lax" as const,
    secure: config.appBaseUrl.protocol === "https:",
  };
}

export async function getSession() {
  const value = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!value) return null;
  const config = loadOidcConfig();
  return readSession(value, config.sessionSecret);
}

export function setTransactionCookie(
  response: NextResponse,
  transaction: AuthTransaction,
  config: OidcConfig,
) {
  response.cookies.set(
    TRANSACTION_COOKIE,
    seal(transaction, config.sessionSecret),
    cookieOptions(config, 10 * 60),
  );
}

export function setSessionCookie(
  response: NextResponse,
  session: AuthSession,
  config: OidcConfig,
) {
  const maxAge = Math.max(0, Math.floor((session.expiresAt - Date.now()) / 1000));
  response.cookies.set(
    SESSION_COOKIE,
    seal(session, config.sessionSecret),
    cookieOptions(config, maxAge),
  );
}

export function clearAuthCookies(response: NextResponse, config: OidcConfig) {
  const expired = cookieOptions(config, 0);
  response.cookies.set(SESSION_COOKIE, "", expired);
  response.cookies.set(TRANSACTION_COOKIE, "", expired);
}
