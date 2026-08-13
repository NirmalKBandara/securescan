"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { ErrorMessage } from "@/components/error-message";
import { LoadingState } from "@/components/loading-state";
import { StatusBadge } from "@/components/status-badge";
import { scansApi, SecureScanApiError } from "@/lib/api/client";
import type { ScanHistoryItem, ScanStatus } from "@/lib/api/types";
import { formatUtcDateTime } from "@/lib/format/date-time";

type StatusFilter = "all" | ScanStatus;

const statusOptions: Array<{ value: StatusFilter; label: string }> = [
  { value: "all", label: "All statuses" },
  { value: "queued", label: "Queued" },
  { value: "accepted", label: "Accepted" },
  { value: "running", label: "Running" },
  { value: "completed", label: "Completed" },
  { value: "failed", label: "Failed" },
  { value: "blocked", label: "Blocked" },
];

export function ScanHistory() {
  const [items, setItems] = useState<ScanHistoryItem[]>([]);
  const [status, setStatus] = useState<StatusFilter>("all");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<SecureScanApiError | null>(null);
  const [requestGeneration, setRequestGeneration] = useState(0);

  useEffect(() => {
    let active = true;
    const controller = new AbortController();

    scansApi.list({ pageSize: 100, signal: controller.signal })
      .then((history) => {
        if (!active) return;
        setItems(history.items);
        setError(null);
      })
      .catch((caught) => {
        if (!active || (caught instanceof DOMException && caught.name === "AbortError")) return;
        setError(caught instanceof SecureScanApiError
          ? caught
          : new SecureScanApiError("Unable to reach SecureScan.", 0));
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
      controller.abort();
    };
  }, [requestGeneration]);

  const retry = useCallback(() => {
    setLoading(true);
    setError(null);
    setRequestGeneration((generation) => generation + 1);
  }, []);

  const visibleItems = useMemo(
    () => status === "all" ? items : items.filter((item) => item.status === status),
    [items, status],
  );

  if (loading) return <LoadingState label="Loading scan history" />;

  if (error) {
    return (
      <ErrorMessage
        title="Unable to load scan history"
        message={error.message}
        requestId={error.requestId}
        action={<button className="button secondary" type="button" onClick={retry}>Try again</button>}
      />
    );
  }

  if (items.length === 0) {
    return (
      <section className="card empty-state">
        <span className="radar" aria-hidden="true">↺</span>
        <h2>No scan history yet</h2>
        <p>Completed and in-progress scans will be listed here.</p>
        <Link href="/scans/new">Submit your first scan</Link>
      </section>
    );
  }

  return (
    <section className="card history-card" aria-labelledby="history-heading">
      <div className="history-toolbar">
        <div>
          <p className="eyebrow">Durable jobs</p>
          <h2 id="history-heading">Recent scans</h2>
        </div>
        <div className="history-filter">
          <label htmlFor="history-status">Filter by status</label>
          <select
            id="history-status"
            value={status}
            onChange={(event) => setStatus(event.target.value as StatusFilter)}
          >
            {statusOptions.map((option) => (
              <option key={option.value} value={option.value}>{option.label}</option>
            ))}
          </select>
        </div>
      </div>

      {visibleItems.length === 0 ? (
        <div className="history-empty" role="status">
          No scans match the selected status.
        </div>
      ) : (
        <div className="table-scroll" tabIndex={0} aria-label="Scan history table">
          <table>
            <thead>
              <tr>
                <th scope="col">Target</th>
                <th scope="col">Ports</th>
                <th scope="col">Status</th>
                <th scope="col">Created</th>
                <th scope="col"><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              {visibleItems.map((scan) => (
                <tr key={scan.id}>
                  <td data-label="Target"><Link className="history-target" href={`/scans/${encodeURIComponent(scan.id)}`}>{scan.target}</Link></td>
                  <td data-label="Ports">{scan.startPort}–{scan.endPort}</td>
                  <td data-label="Status"><StatusBadge status={scan.status} /></td>
                  <td data-label="Created"><time dateTime={scan.createdAt}>{formatUtcDateTime(scan.createdAt)}</time></td>
                  <td data-label="Action"><Link className="history-link" href={`/scans/${encodeURIComponent(scan.id)}`}>View scan<span className="sr-only"> for {scan.target}</span></Link></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
