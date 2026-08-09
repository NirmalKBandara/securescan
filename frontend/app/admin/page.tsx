import type { Metadata } from "next";
import { PageIntro } from "@/components/page-intro";

export const metadata: Metadata = { title: "Administration" };
export default function AdminPage() {
  return <><PageIntro eyebrow="Administration" title="Platform controls" description="Manage target policies and audit visibility after role-based access is connected." /><section className="admin-grid"><article className="card"><h2>Allowed targets</h2><p>Target policy administration will be available to authorized administrators.</p><span className="pill">Planned</span></article><article className="card"><h2>Audit events</h2><p>Lifecycle activity is recorded by the service without sensitive request data.</p><span className="pill success">Active in API</span></article></section></>;
}
