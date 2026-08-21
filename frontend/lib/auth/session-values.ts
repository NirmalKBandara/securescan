import { unseal } from "./session-codec";
import type { OidcClientKind } from "./config-values";

export interface AuthTransaction {
  clientKind: OidcClientKind;
  codeVerifier: string;
  expiresAt: number;
  nonce: string;
  returnTo: string;
  state: string;
}

export interface AuthSession {
  accessToken: string;
  clientKind: OidcClientKind;
  email?: string;
  expiresAt: number;
  idToken: string;
  issuer: string;
  name: string;
  roles: string[];
  subject: string;
}

export function readTransaction(
  value: string | undefined,
  secret: string,
  now = Date.now(),
) {
  const transaction = unseal<AuthTransaction>(value, secret);
  if (
    !transaction ||
    (transaction.clientKind !== "user" && transaction.clientKind !== "admin") ||
    transaction.expiresAt <= now
  ) return null;
  return transaction;
}

export function readSession(
  value: string | undefined,
  secret: string,
  now = Date.now(),
) {
  const session = unseal<AuthSession>(value, secret);
  if (
    !session ||
    (session.clientKind !== "user" && session.clientKind !== "admin") ||
    session.expiresAt <= now ||
    !session.subject ||
    !session.issuer ||
    !session.accessToken
  ) {
    return null;
  }
  return session;
}
