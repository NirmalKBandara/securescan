export type ScanStatus = "queued" | "accepted" | "running" | "completed" | "failed" | "blocked";
export type PortState = "open" | "closed";

export interface CreateScanRequest {
  target: string;
  startPort: number;
  endPort: number;
  authorized: boolean;
}

export interface ScanSummary {
  id: string;
  status: ScanStatus;
  target: string;
  startPort: number;
  endPort: number;
}

export interface ScanHistoryItem extends ScanSummary {
  createdAt: string;
  updatedAt: string;
}

export interface PortResult {
  address: string;
  port: number;
  state: PortState;
}

export interface ScanResult {
  target: string;
  startPort: number;
  endPort: number;
  results: PortResult[];
  durationNanos: number;
}

export interface ScanDetail extends ScanHistoryItem {
  failureCode?: string | null;
  result?: ScanResult | null;
}

export interface ScanHistory {
  items: ScanHistoryItem[];
  pageSize: number;
}

export type ApiErrorCode =
  | "INVALID_TARGET" | "INVALID_PORT_RANGE" | "INVALID_SCAN_ID"
  | "INVALID_REQUEST" | "BLOCKED_TARGET" | "SCAN_NOT_FOUND"
  | "SCANNER_UNAVAILABLE" | "PERSISTENCE_UNAVAILABLE"
  | "JOB_LIMIT_REACHED" | "INTERNAL_ERROR";

export interface ApiErrorBody {
  code: ApiErrorCode;
  message: string;
  requestId: string;
  details?: Record<string, unknown>;
}

export interface SuccessEnvelope<T> { success: true; data: T }
export interface ErrorEnvelope { success: false; error: ApiErrorBody }
