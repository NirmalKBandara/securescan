import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

type RouteContext = { params: Promise<{ path: string[] }> };

function errorResponse(status: number, code: string, message: string) {
  return NextResponse.json({
    success: false,
    error: { code, message, requestId: crypto.randomUUID() },
  }, { status });
}

function backendConfiguration() {
  const baseUrl = process.env.BALLERINA_API_BASE_URL?.trim().replace(/\/$/, "");
  const mode = process.env.SECURESCAN_API_MODE?.trim() || "direct";
  if (!baseUrl || (mode !== "direct" && mode !== "gateway")) {
    throw new Error("SecureScan API proxy configuration is invalid");
  }
  const gatewaySecret = process.env.SECURESCAN_API_GATEWAY_SECRET?.trim();
  if (mode === "direct" && (!gatewaySecret || gatewaySecret.length < 32)) {
    throw new Error("SECURESCAN_API_GATEWAY_SECRET must contain at least 32 characters");
  }
  return { baseUrl, gatewaySecret, mode };
}

async function proxy(request: NextRequest, context: RouteContext) {
  const session = await getSession();
  if (!session) {
    return errorResponse(401, "AUTHENTICATION_REQUIRED", "Sign in to use SecureScan");
  }

  let config: ReturnType<typeof backendConfiguration>;
  try {
    config = backendConfiguration();
  } catch {
    return errorResponse(503, "API_PROXY_UNAVAILABLE", "The SecureScan API is not configured");
  }

  const { path } = await context.params;
  if (!path.length || path.some((segment) => !segment || segment === "." || segment === "..")) {
    return errorResponse(400, "INVALID_REQUEST", "The API path is invalid");
  }

  const upstream = new URL(`${config.baseUrl}/${path.map(encodeURIComponent).join("/")}`);
  upstream.search = request.nextUrl.search;
  const headers = new Headers({ Accept: "application/json" });
  const contentType = request.headers.get("content-type");
  if (contentType) headers.set("Content-Type", contentType);

  if (config.mode === "gateway") {
    headers.set("Authorization", `Bearer ${session.accessToken}`);
  } else {
    headers.set("X-SecureScan-Subject", session.subject);
    headers.set("X-SecureScan-Roles", session.roles.join(","));
    headers.set("X-SecureScan-Gateway-Secret", config.gatewaySecret!);
  }

  try {
    const response = await fetch(upstream, {
      body: request.method === "GET" || request.method === "HEAD" ? undefined : await request.arrayBuffer(),
      cache: "no-store",
      headers,
      method: request.method,
      redirect: "manual",
    });
    const responseHeaders = new Headers();
    for (const name of ["content-type", "location", "x-request-id"]) {
      const value = response.headers.get(name);
      if (value) responseHeaders.set(name, value);
    }
    return new NextResponse(response.body, {
      headers: responseHeaders,
      status: response.status,
      statusText: response.statusText,
    });
  } catch {
    return errorResponse(503, "API_PROXY_UNAVAILABLE", "The SecureScan API is unavailable");
  }
}

export function GET(request: NextRequest, context: RouteContext) {
  return proxy(request, context);
}

export function POST(request: NextRequest, context: RouteContext) {
  return proxy(request, context);
}
