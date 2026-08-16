"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { StatusBadge } from "@/components/status-badge";
import { adminApi, SecureScanApiError } from "@/lib/api/client";
import type {
  AdminScan, AdminUsage, AllowedTarget, AllowedTargetKind, AuditEvent, ScanStatus,
} from "@/lib/api/types";
import { formatUtcDateTime } from "@/lib/format/date-time";

const statuses: ScanStatus[] = ["queued", "running", "completed", "failed", "blocked"];
const emptyUsage: AdminUsage = {
  totalUsers: 0, totalScans: 0, queuedScans: 0, runningScans: 0,
  completedScans: 0, failedScans: 0, blockedScans: 0, enabledAllowedTargets: 0,
};

function errorMessage(error: unknown) {
  return error instanceof SecureScanApiError ? error.message : "Administrator data could not be loaded";
}

export function AdminDashboard() {
  const [usage, setUsage] = useState(emptyUsage);
  const [scans, setScans] = useState<AdminScan[]>([]);
  const [auditEvents, setAuditEvents] = useState<AuditEvent[]>([]);
  const [targets, setTargets] = useState<AllowedTarget[]>([]);
  const [owner, setOwner] = useState("");
  const [status, setStatus] = useState<ScanStatus | "">("");
  const [loading, setLoading] = useState(true);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");

  const loadDashboard = useCallback(async (signal?: AbortSignal) => {
    setLoading(true);
    setError("");
    try {
      const [nextUsage, nextScans, nextAudit, nextTargets] = await Promise.all([
        adminApi.usage({ signal }), adminApi.scans({ signal }),
        adminApi.auditLogs({ signal }), adminApi.allowedTargets({ signal }),
      ]);
      setUsage(nextUsage);
      setScans(nextScans.items);
      setAuditEvents(nextAudit.items);
      setTargets(nextTargets.items);
    } catch (caught) {
      if (!(caught instanceof DOMException && caught.name === "AbortError")) setError(errorMessage(caught));
    } finally {
      if (!signal?.aborted) setLoading(false);
    }
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    const timeout = window.setTimeout(() => void loadDashboard(controller.signal), 0);
    return () => {
      window.clearTimeout(timeout);
      controller.abort();
    };
  }, [loadDashboard]);

  async function filterScans(event: FormEvent) {
    event.preventDefault();
    setError("");
    setLoading(true);
    try {
      const result = await adminApi.scans({ ownerSubject: owner.trim() || undefined, status: status || undefined });
      setScans(result.items);
      setNotice(`Showing ${result.items.length} matching scan${result.items.length === 1 ? "" : "s"}.`);
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setLoading(false);
    }
  }

  async function createTarget(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const targetKind = String(form.get("targetKind")) as AllowedTargetKind;
    const target = String(form.get("target")).trim();
    const start = String(form.get("startPort") || "");
    const end = String(form.get("endPort") || "");
    setError("");
    try {
      await adminApi.createAllowedTarget({
        targetKind, target,
        ...(start && end ? { startPort: Number(start), endPort: Number(end) } : {}),
      });
      event.currentTarget.reset();
      setNotice(`${target} is now allowed.`);
      await loadDashboard();
    } catch (caught) {
      setError(errorMessage(caught));
    }
  }

  async function disableTarget(target: AllowedTarget) {
    if (!window.confirm(`Disable ${target.target}? Existing audit history will be retained.`)) return;
    setError("");
    try {
      await adminApi.disableAllowedTarget(target.id);
      setTargets((current) => current.map((item) => item.id === target.id ? { ...item, enabled: false } : item));
      setUsage((current) => ({ ...current, enabledAllowedTargets: Math.max(0, current.enabledAllowedTargets - 1) }));
      setNotice(`${target.target} was disabled.`);
    } catch (caught) {
      setError(errorMessage(caught));
    }
  }

  return <div className="admin-stack">
    <div className="admin-stats" aria-label="Platform usage">
      <Stat label="Users" value={usage.totalUsers} />
      <Stat label="Total scans" value={usage.totalScans} />
      <Stat label="Active" value={usage.queuedScans + usage.runningScans} />
      <Stat label="Blocked / failed" value={usage.blockedScans + usage.failedScans} tone="warning" />
      <Stat label="Allowed targets" value={usage.enabledAllowedTargets} />
    </div>
    <div className="admin-feedback" aria-live="polite" aria-atomic="true">
      {loading && <span>Refreshing administrator data…</span>}
      {notice && !loading && <span>{notice}</span>}
      {error && <span role="alert" className="field-error">{error}</span>}
    </div>

    <section className="card admin-panel" aria-labelledby="admin-scans-title">
      <div className="admin-panel-heading"><div><p className="eyebrow">Visibility</p><h2 id="admin-scans-title">All scans</h2></div></div>
      <form className="admin-filters" onSubmit={filterScans}>
        <div className="field compact"><label htmlFor="ownerSubject">User subject</label><input id="ownerSubject" value={owner} onChange={(event) => setOwner(event.target.value)} maxLength={255} placeholder="All users" /></div>
        <div className="field compact"><label htmlFor="scanStatus">Status</label><select id="scanStatus" value={status} onChange={(event) => setStatus(event.target.value as ScanStatus | "")}><option value="">All statuses</option>{statuses.map((item) => <option key={item} value={item}>{item}</option>)}</select></div>
        <button className="button secondary" type="submit" disabled={loading}>Apply filters</button>
      </form>
      <div className="table-scroll" tabIndex={0}>
        <table><caption className="sr-only">Scans across all SecureScan users</caption><thead><tr><th>User</th><th>Target</th><th>Status</th><th>Failure</th><th>Created</th></tr></thead><tbody>
          {scans.map((scan) => <tr key={scan.id}><td data-label="User">{scan.ownerSubject}</td><td data-label="Target">{scan.target}<small className="table-subtext">Ports {scan.startPort}–{scan.endPort}</small></td><td data-label="Status"><StatusBadge status={scan.status} /></td><td data-label="Failure">{scan.failureCode || "—"}</td><td data-label="Created">{formatUtcDateTime(scan.createdAt)}</td></tr>)}
        </tbody></table>{!scans.length && !loading && <p className="history-empty">No scans match these filters.</p>}
      </div>
    </section>

    <section className="card admin-panel" aria-labelledby="targets-title">
      <div className="admin-panel-heading"><div><p className="eyebrow">Policy</p><h2 id="targets-title">Allowed targets</h2></div><span className="pill success">{usage.enabledAllowedTargets} enabled</span></div>
      <form className="target-form" onSubmit={createTarget}>
        <div className="field compact"><label htmlFor="targetKind">Type</label><select id="targetKind" name="targetKind"><option>HOSTNAME</option><option>IP</option><option>CIDR</option></select></div>
        <div className="field compact target-value"><label htmlFor="target">Target</label><input id="target" name="target" required maxLength={253} placeholder="scan.example.com or 192.0.2.0/24" /></div>
        <div className="field compact"><label htmlFor="startPort">Start port</label><input id="startPort" name="startPort" inputMode="numeric" type="number" min="1" max="65535" /></div>
        <div className="field compact"><label htmlFor="endPort">End port</label><input id="endPort" name="endPort" inputMode="numeric" type="number" min="1" max="65535" /></div>
        <button className="button primary" type="submit">Add target</button>
      </form>
      <div className="table-scroll" tabIndex={0}><table><caption className="sr-only">Configured allowed scan targets</caption><thead><tr><th>Target</th><th>Type</th><th>Port policy</th><th>State</th><th>Action</th></tr></thead><tbody>
        {targets.map((target) => <tr key={target.id}><td data-label="Target">{target.target}</td><td data-label="Type">{target.targetKind}</td><td data-label="Port policy">{target.startPort && target.endPort ? `${target.startPort}–${target.endPort}` : "Any authorized range"}</td><td data-label="State"><span className={`pill ${target.enabled ? "success" : ""}`}>{target.enabled ? "Enabled" : "Disabled"}</span></td><td data-label="Action">{target.enabled ? <button className="text-button danger" type="button" onClick={() => void disableTarget(target)}>Disable</button> : "—"}</td></tr>)}
      </tbody></table></div>
    </section>

    <section className="card admin-panel" aria-labelledby="audit-title">
      <div className="admin-panel-heading"><div><p className="eyebrow">Accountability</p><h2 id="audit-title">Audit log</h2></div></div>
      <div className="table-scroll" tabIndex={0}><table><caption className="sr-only">Latest immutable administrator and scan lifecycle audit events</caption><thead><tr><th>Time</th><th>Action</th><th>Actor</th><th>User</th><th>Outcome</th></tr></thead><tbody>
        {auditEvents.map((event) => <tr key={event.id}><td data-label="Time">{formatUtcDateTime(event.occurredAt)}</td><td data-label="Action"><code>{event.action}</code></td><td data-label="Actor">{event.actorSubject || event.actorType}</td><td data-label="User">{event.ownerSubject || "—"}</td><td data-label="Outcome"><span className={`pill ${event.outcome === "SUCCESS" ? "success" : ""}`}>{event.outcome}</span></td></tr>)}
      </tbody></table>{!auditEvents.length && !loading && <p className="history-empty">No audit events have been recorded.</p>}</div>
    </section>
  </div>;
}

function Stat({ label, value, tone }: { label: string; value: number; tone?: "warning" }) {
  return <article className={`card admin-stat ${tone ? `admin-stat-${tone}` : ""}`}><span>{label}</span><strong>{value.toLocaleString()}</strong></article>;
}
