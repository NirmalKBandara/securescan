import { StatusBadge } from "@/components/status-badge";
import type { ScanHistoryItem } from "@/lib/api/types";

const activeStatuses = new Set(["queued", "accepted", "running"]);

export function ScanStatus({ scan }: { scan: ScanHistoryItem }) {
  const active = activeStatuses.has(scan.status);
  return (
    <article className="card scan-status" aria-labelledby={`scan-${scan.id}`} aria-live={active ? "polite" : "off"}>
      <div className="scan-status-heading">
        <div>
          <p className="eyebrow">Scan job</p>
          <h2 id={`scan-${scan.id}`}>{scan.target}</h2>
        </div>
        <StatusBadge status={scan.status} />
      </div>
      <dl className="scan-meta">
        <div><dt>Port range</dt><dd>{scan.startPort}–{scan.endPort}</dd></div>
        <div><dt>Created</dt><dd><time dateTime={scan.createdAt}>{formatDate(scan.createdAt)}</time></dd></div>
        <div><dt>Last updated</dt><dd><time dateTime={scan.updatedAt}>{formatDate(scan.updatedAt)}</time></dd></div>
      </dl>
      {active && <div className="scan-progress" role="progressbar" aria-label={`${scan.status} scan progress`} aria-valuetext={scan.status}><span className={`progress-${scan.status}`} /></div>}
    </article>
  );
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short", timeZone: "UTC" }).format(new Date(value));
}
