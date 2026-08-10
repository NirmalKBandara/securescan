import type { ScanStatus } from "@/lib/api/types";

const statusLabels: Record<ScanStatus, string> = {
  queued: "Queued",
  accepted: "Accepted",
  running: "Running",
  completed: "Completed",
  failed: "Failed",
  blocked: "Blocked",
};

export function StatusBadge({ status }: { status: ScanStatus }) {
  return (
    <span className={`status-badge status-${status}`}>
      <span className="status-dot" aria-hidden="true" />
      {statusLabels[status]}
    </span>
  );
}
