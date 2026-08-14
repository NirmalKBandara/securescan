import { describe, expect, it } from "vitest";
import { seal } from "./session-codec";
import { readSession, readTransaction, type AuthSession, type AuthTransaction } from "./session-values";

const secret = "0123456789abcdef0123456789abcdef";
const now = Date.now();

describe("auth cookie values", () => {
  it("accepts live sessions and rejects expired sessions", () => {
    const session: AuthSession = {
      accessToken: "access-token",
      expiresAt: now + 60_000,
      idToken: "id-token",
      issuer: "https://localhost:9443/oauth2/token",
      name: "Alice",
      roles: [],
      subject: "alice-id",
    };
    expect(readSession(seal(session, secret), secret, now)).toEqual(session);
    expect(readSession(seal({ ...session, expiresAt: now }, secret), secret, now)).toBeNull();
  });

  it("rejects expired OIDC transactions", () => {
    const transaction: AuthTransaction = {
      codeVerifier: "verifier",
      expiresAt: now,
      nonce: "nonce",
      returnTo: "/dashboard",
      state: "state",
    };
    expect(readTransaction(seal(transaction, secret), secret, now)).toBeNull();
  });
});
