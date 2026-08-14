import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { getSession } from "@/lib/auth/session";
import { GET, POST } from "./route";

vi.mock("server-only", () => ({}));
vi.mock("@/lib/auth/session", () => ({ getSession: vi.fn() }));

const session = {
  accessToken: "identity-server-access-token",
  expiresAt: Date.now() + 60_000,
  idToken: "id-token",
  issuer: "https://localhost:9443/oauth2/token",
  name: "SecureScan User",
  roles: ["securescan-user"],
  subject: "user-123",
};

const context = (path: string[]) => ({ params: Promise.resolve({ path }) });

describe("authenticated API Manager proxy", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    process.env.SECURESCAN_API_MODE = "gateway";
    process.env.API_MANAGER_GATEWAY_URL = "https://localhost:8243/securescan/v1";
    vi.mocked(getSession).mockResolvedValue(session);
  });

  it("forwards the unchanged server-side access token through the Gateway", async () => {
    const upstream = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      success: true,
      data: { id: "scan-123", status: "queued" },
    }), {
      headers: { "Content-Type": "application/json", "X-Request-ID": "request-123" },
      status: 202,
    }));
    vi.stubGlobal("fetch", upstream);

    const response = await POST(new NextRequest(
      "http://localhost:3000/backend/api/v1/scans?source=browser",
      {
        body: JSON.stringify({ target: "scanme.nmap.org", authorized: true }),
        headers: { "Content-Type": "application/json" },
        method: "POST",
      },
    ), context(["api", "v1", "scans"]));

    expect(response.status).toBe(202);
    expect(response.headers.get("x-request-id")).toBe("request-123");
    expect(await response.json()).toMatchObject({ success: true });

    const [url, init] = upstream.mock.calls[0] as [URL, RequestInit];
    expect(url.toString()).toBe(
      "https://localhost:8243/securescan/v1/api/v1/scans?source=browser",
    );
    const headers = new Headers(init.headers);
    expect(headers.get("Authorization")).toBe(
      "Bearer identity-server-access-token",
    );
    expect(headers.has("X-SecureScan-Subject")).toBe(false);
    expect(headers.has("X-SecureScan-Roles")).toBe(false);
    expect(headers.has("X-SecureScan-Gateway-Secret")).toBe(false);
  });

  it("normalizes non-envelope API Manager failures for the frontend", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(
      "Authentication failure",
      {
        headers: { "Content-Type": "text/plain", "X-Correlation-ID": "gateway-123" },
        status: 403,
      },
    )));

    const response = await GET(
      new NextRequest("http://localhost:3000/backend/api/v1/scans"),
      context(["api", "v1", "scans"]),
    );

    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({
      success: false,
      error: {
        code: "GATEWAY_ACCESS_DENIED",
        message: "Your account cannot perform this API request",
        requestId: "gateway-123",
      },
    });
  });

  it("rejects a successful but malformed upstream response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("not json", {
      status: 200,
    })));

    const response = await GET(
      new NextRequest("http://localhost:3000/backend/api/v1/scans"),
      context(["api", "v1", "scans"]),
    );

    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({
      success: false,
      error: { code: "API_GATEWAY_UNAVAILABLE" },
    });
  });
});
