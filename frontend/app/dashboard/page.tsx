import type { Metadata } from "next";
import Link from "next/link";
import { PageIntro } from "@/components/page-intro";

export const metadata: Metadata = { title: "Dashboard" };
export default function DashboardPage() {
  return <>
    <PageIntro eyebrow="Overview" title="Security scanning, under control" description="Track authorized scans and review findings from one focused workspace." action={<Link className="button primary" href="/scans/new">Start a scan</Link>} />
    <section className="stats-grid" aria-label="Scan summary">
      <article className="card stat"><span>Active scans</span><strong>0</strong><small>Nothing currently running</small></article>
      <article className="card stat"><span>Completed</span><strong>0</strong><small>All-time scans</small></article>
      <article className="card stat"><span>Open ports</span><strong>0</strong><small>Across latest results</small></article>
    </section>
    <section className="card empty-state"><span className="radar" aria-hidden="true">⌁</span><h2>No recent scans</h2><p>Your latest scan activity will appear here.</p><Link href="/scans/new">Create your first scan <span aria-hidden="true">→</span></Link></section>
  </>;
}
