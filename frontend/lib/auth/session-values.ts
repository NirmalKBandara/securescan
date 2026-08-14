import { unseal } from "./session-codec";

export interface AuthTransaction {
  codeVerifier: string;
  expiresAt: number;
  nonce: string;
  returnTo: string;
  state: string;
}

export interface AuthSession {
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
  if (!transaction || transaction.expiresAt <= now) return null;
  return transaction;
}

export function readSession(
  value: string | undefined,
  secret: string,
  now = Date.now(),
) {
  const session = unseal<AuthSession>(value, secret);
  if (!session || session.expiresAt <= now || !session.subject || !session.issuer) {
    return null;
  }
  return session;
}
