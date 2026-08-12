"use client";

import { ErrorMessage } from "@/components/error-message";
import { LoadingState } from "@/components/loading-state";
import { ResultsTable } from "@/components/results-table";
import { ScanStatus } from "@/components/scan-status";
import { useScanDetail } from "@/hooks/use-scan-detail";
import { getScanFailureReason } from "@/lib/scans/failure-reasons";

export function ScanDetailView({ id }: { id: string }) {
  const { scan, loading, error, retrying, retry } = useScanDetail(id);

  if (loading) return <LoadingState label="Loading scan details" />;

  if (!scan && error) {
    return (
      <ErrorMessage
        title="Unable to load scan"
        message={error.message}
        requestId={error.requestId}
        action={<button className="button secondary" type="button" onClick={retry}>Try again</button>}
      />
    );
  }

  if (!scan) return null;

  const terminalFailure = scan.status === "failed" || scan.status === "blocked";
  return (
    <div className="detail-stack">
      <ScanStatus scan={scan} />
      {error && (
        <ErrorMessage
          title="Status update delayed"
          message={retrying ? "The latest status could not be loaded. SecureScan will retry automatically." : error.message}
          requestId={error.requestId}
          action={<button className="button secondary" type="button" onClick={retry}>Retry now</button>}
        />
      )}
      {terminalFailure && (
        <section className={`card scan-outcome outcome-${scan.status}`} aria-labelledby="scan-outcome-title">
          <p className="eyebrow">{scan.status === "blocked" ? "Safety policy" : "Scan failure"}</p>
          <h2 id="scan-outcome-title">{scan.status === "blocked" ? "Target blocked" : "Scan unsuccessful"}</h2>
          <p>{getScanFailureReason(scan.status, scan.failureCode)}</p>
        </section>
      )}
      {scan.status === "completed" && <ResultsTable results={scan.result?.results ?? []} />}
    </div>
  );
}
