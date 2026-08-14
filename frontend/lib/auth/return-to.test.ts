import { describe, expect, it } from "vitest";
import { safeReturnTo } from "./return-to";

describe("safeReturnTo", () => {
  it("preserves an internal path, query, and fragment", () => {
    expect(safeReturnTo("/history?status=completed#results"))
      .toBe("/history?status=completed#results");
  });

  it.each([
    undefined,
    "https://attacker.example/steal",
    "//attacker.example/steal",
    "/auth/callback",
    `/${"x".repeat(2050)}`,
  ])("falls back for an unsafe destination", (value) => {
    expect(safeReturnTo(value)).toBe("/dashboard");
  });
});
