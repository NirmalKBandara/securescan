import { describe, expect, it } from "vitest";
import { isScanTarget, scanFormSchema } from "./scan";

describe("scanFormSchema", () => {
  it("accepts and normalizes an authorized hostname request", () => {
    expect(scanFormSchema.parse({
      target: "  scanme.nmap.org  ",
      startPort: 1,
      endPort: 443,
      authorized: true,
    })).toEqual({
      target: "scanme.nmap.org",
      startPort: 1,
      endPort: 443,
      authorized: true,
    });
  });

  it.each(["https://example.com", "bad target", "example..com", "256.1.1.1"])(
    "rejects malformed target %s",
    (target) => expect(isScanTarget(target)).toBe(false),
  );

  it.each(["scanme.nmap.org", "192.0.2.10", "2001:db8::1"])(
    "accepts target syntax %s",
    (target) => expect(isScanTarget(target)).toBe(true),
  );

  it("rejects out-of-order ports", () => {
    const result = scanFormSchema.safeParse({
      target: "scanme.nmap.org",
      startPort: 443,
      endPort: 80,
      authorized: true,
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.flatten().fieldErrors.endPort).toContain(
        "End port must be greater than or equal to start port",
      );
    }
  });

  it("accepts exactly 1,000 ports and rejects 1,001", () => {
    expect(scanFormSchema.safeParse({
      target: "scanme.nmap.org",
      startPort: 1,
      endPort: 1000,
      authorized: true,
    }).success).toBe(true);
    const result = scanFormSchema.safeParse({
      target: "scanme.nmap.org",
      startPort: 1,
      endPort: 1001,
      authorized: true,
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.flatten().fieldErrors.endPort).toContain(
        "A scan can include at most 1000 ports",
      );
    }
  });

  it("requires explicit authorization", () => {
    const result = scanFormSchema.safeParse({
      target: "scanme.nmap.org",
      startPort: 1,
      endPort: 100,
      authorized: false,
    });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.flatten().fieldErrors.authorized).toContain(
        "Confirm that you are authorized to scan this target",
      );
    }
  });
});
