import { env } from "@/lib/env";
import type {
  AdminScanList, AdminUsage, AllowedTarget, AllowedTargetList, AuditEventList,
  CreateAllowedTargetRequest, CreateScanRequest, ErrorEnvelope, ScanDetail,
  ScanHistory, ScanStatus, ScanSummary, SuccessEnvelope,
} from "./types";

export class SecureScanApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code = "UNKNOWN_ERROR",
    readonly requestId?: string,
  ) {
    super(message);
    this.name = "SecureScanApiError";
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${env.apiBaseUrl}${path}`, {
    ...init,
    headers: { Accept: "application/json", ...init?.headers },
  });
  let body: SuccessEnvelope<T> | ErrorEnvelope;
  try {
    body = await response.json() as SuccessEnvelope<T> | ErrorEnvelope;
  } catch {
    throw new SecureScanApiError("The API returned an invalid response", response.status);
  }
  if (!response.ok || !body.success) {
    const failure = body as ErrorEnvelope;
    throw new SecureScanApiError(
      failure.error?.message || "SecureScan request failed",
      response.status,
      failure.error?.code,
      failure.error?.requestId || response.headers.get("X-Request-ID") || undefined,
    );
  }
  return body.data;
}

export const scansApi = {
  create(input: CreateScanRequest) {
    return request<ScanSummary>("/api/v1/scans", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(input),
    });
  },
  get(id: string, options: { signal?: AbortSignal } = {}) {
    return request<ScanDetail>(`/api/v1/scans/${encodeURIComponent(id)}`, {
      signal: options.signal,
    });
  },
  list(options: { pageSize?: number; cursorCreatedAt?: string; cursorId?: string; signal?: AbortSignal } = {}) {
    const query = new URLSearchParams();
    if (options.pageSize) query.set("pageSize", String(options.pageSize));
    if (options.cursorCreatedAt) query.set("cursorCreatedAt", options.cursorCreatedAt);
    if (options.cursorId) query.set("cursorId", options.cursorId);
    const suffix = query.size ? `?${query}` : "";
    return request<ScanHistory>(`/api/v1/scans${suffix}`, { signal: options.signal });
  },
};

export const adminApi = {
  scans(options: { ownerSubject?: string; status?: ScanStatus; signal?: AbortSignal } = {}) {
    const query = new URLSearchParams({ pageSize: "100" });
    if (options.ownerSubject) query.set("ownerSubject", options.ownerSubject);
    if (options.status) query.set("status", options.status);
    return request<AdminScanList>(`/api/v1/admin/scans?${query}`, { signal: options.signal });
  },
  usage(options: { signal?: AbortSignal } = {}) {
    return request<AdminUsage>("/api/v1/admin/usage", { signal: options.signal });
  },
  auditLogs(options: { signal?: AbortSignal } = {}) {
    return request<AuditEventList>("/api/v1/admin/audit-logs?pageSize=100", { signal: options.signal });
  },
  allowedTargets(options: { signal?: AbortSignal } = {}) {
    return request<AllowedTargetList>(
      "/api/v1/admin/allowed-targets?includeDisabled=true&pageSize=100",
      { signal: options.signal },
    );
  },
  createAllowedTarget(input: CreateAllowedTargetRequest) {
    return request<AllowedTarget>("/api/v1/admin/allowed-targets", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(input),
    });
  },
  disableAllowedTarget(id: string) {
    return request<AllowedTarget>(`/api/v1/admin/allowed-targets/${encodeURIComponent(id)}`, {
      method: "DELETE",
    });
  },
};
