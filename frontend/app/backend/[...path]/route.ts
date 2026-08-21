import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth/session";
import { APP_ROLES, hasRole } from "@/lib/auth/authorization";
import { loadApiProxyConfig } from "@/lib/api/proxy-config";

export const dynamic = "force-dynamic";

type RouteContext = { params: Promise<{ path: string[] }> };

function errorResponse(
  status: number,
  code: string,
  message: string,
  requestId = crypto.randomUUID(),
  headers?: HeadersInit,
) {
  return NextResponse.json({
    success: false,
    error: { code, message, requestId },
  }, { headers, status });
}

function isSecureScanEnvelope(value: unknown) {
  if (!value || typeof value !== "object") return false;
  const envelope = value as Record<string, unknown>;
  if (envelope.success === true) return "data" in envelope;
  if (envelope.success !== false || !envelope.error || typeof envelope.error !== "object") {
    return false;
  }
  const error = envelope.error as Record<string, unknown>;
  return typeof error.code === "string" && typeof error.message === "string";
}

function gatewayFailure(status: number) {
  if (status === 401) {
    return ["GATEWAY_AUTHENTICATION_FAILED", "Your API session is no longer valid"] as const;
  }
  if (status === 403) {
    return ["GATEWAY_ACCESS_DENIED", "Your account cannot perform this API request"] as const;
  }
  if (status === 429) {
    return ["GATEWAY_RATE_LIMITED", "Too many API requests; try again shortly"] as const;
  }
  if (status >= 400 && status < 500) {
    return ["GATEWAY_REQUEST_REJECTED", "API Manager rejected the request"] as const;
  }
  return ["API_GATEWAY_UNAVAILABLE", "API Manager returned an unusable response"] as const;
}

async function proxy(request: NextRequest, context: RouteContext) {
  const session = await getSession();
  if (!session) {
    return errorResponse(401, "AUTHENTICATION_REQUIRED", "Sign in to use SecureScan");
  }

  let config: ReturnType<typeof loadApiProxyConfig>;
  try {
    config = loadApiProxyConfig();
  } catch {
    return errorResponse(503, "API_PROXY_UNAVAILABLE", "The SecureScan API is not configured");
  }

  const { path } = await context.params;
  if (!path.length || path.some((segment) => !segment || segment === "." || segment === "..")) {
    return errorResponse(400, "INVALID_REQUEST", "The API path is invalid");
  }
  if (path[0] === "api" && path[1] === "v1" && path[2] === "admin" &&
      (session.clientKind !== "admin" || !hasRole(session, APP_ROLES.admin))) {
    return errorResponse(403, "ADMIN_AUTHENTICATION_REQUIRED",
      "Sign in with the administrator client to use this resource");
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
    let body: ArrayBuffer | undefined;
    if (request.method !== "GET" && request.method !== "HEAD") {
      const declaredLength = request.headers.get("content-length");
      if (declaredLength && Number(declaredLength) > config.maxRequestBytes) {
        return errorResponse(413, "REQUEST_TOO_LARGE", "The API request body is too large");
      }
      body = await request.arrayBuffer();
      if (body.byteLength > config.maxRequestBytes) {
        return errorResponse(413, "REQUEST_TOO_LARGE", "The API request body is too large");
      }
    }
    const response = await fetch(upstream, {
      body,
      cache: "no-store",
      headers,
      method: request.method,
      redirect: "manual",
      signal: AbortSignal.timeout(config.timeoutMs),
    });
    const responseHeaders = new Headers();
    for (const name of ["content-type", "location", "retry-after", "x-request-id"]) {
      const value = response.headers.get(name);
      if (value) responseHeaders.set(name, value);
    }

    let envelope: unknown;
    try {
      envelope = await response.clone().json();
    } catch {
      envelope = undefined;
    }
    if (!isSecureScanEnvelope(envelope)) {
      const [code, message] = gatewayFailure(response.ok ? 502 : response.status);
      const requestId = response.headers.get("x-request-id")
        || response.headers.get("x-correlation-id")
        || crypto.randomUUID();
      return errorResponse(
        response.ok ? 502 : response.status,
        code,
        message,
        requestId,
        responseHeaders,
      );
    }

    return new NextResponse(response.body, {
      headers: responseHeaders,
      status: response.status,
      statusText: response.statusText,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "TimeoutError") {
      return errorResponse(504, "API_GATEWAY_TIMEOUT", "The SecureScan API timed out");
    }
    return errorResponse(503, "API_PROXY_UNAVAILABLE", "The SecureScan API is unavailable");
  }
}

export function GET(request: NextRequest, context: RouteContext) {
  return proxy(request, context);
}

export function POST(request: NextRequest, context: RouteContext) {
  return proxy(request, context);
}

export function DELETE(request: NextRequest, context: RouteContext) {
  return proxy(request, context);
}
