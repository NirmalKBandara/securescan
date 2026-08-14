import { describe, expect, it } from "vitest";
import { seal, unseal } from "./session-codec";

const secret = "0123456789abcdef0123456789abcdef";

describe("encrypted cookie codec", () => {
  it("round-trips a value without exposing its contents", () => {
    const encoded = seal({ subject: "alice", role: "operator" }, secret);

    expect(encoded).not.toContain("alice");
    expect(unseal(encoded, secret)).toEqual({ subject: "alice", role: "operator" });
  });

  it("rejects tampering, a wrong key, and malformed values", () => {
    const encoded = seal({ subject: "alice" }, secret);
    const parts = encoded.split(".");
    parts[2] = `${parts[2][0] === "a" ? "b" : "a"}${parts[2].slice(1)}`;
    const tampered = parts.join(".");

    expect(unseal(tampered, secret)).toBeNull();
    expect(unseal(encoded, "fedcba9876543210fedcba9876543210")).toBeNull();
    expect(unseal("not-a-cookie", secret)).toBeNull();
  });
});
