import type { ScanStatus } from "@/lib/api/types";

const failureReasons: Record<string, string> = {
  BLOCKED_TARGET: "The target was blocked by the network safety policy.",
  INVALID_TARGET: "The target was not valid for scanning.",
  INVALID_PORT_RANGE: "The requested port range was not valid.",
  SCANNER_UNAVAILABLE: "The scanner service was unavailable.",
  JOB_LIMIT_REACHED: "The scanner could not accept another job.",
  SCANNER_FAILED: "The scanner could not complete this job.",
  PERSISTENCE_UNAVAILABLE: "The scan result could not be saved.",
  INTERNAL_ERROR: "The scan could not be completed.",
};

export function getScanFailureReason(status: ScanStatus, failureCode?: string | null) {
  if (failureCode && failureReasons[failureCode]) return failureReasons[failureCode];
  return status === "blocked"
    ? "The target was blocked by the network safety policy."
    : "The scan could not be completed. Please start a new scan or try again later.";
}
