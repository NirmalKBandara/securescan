import type { Metadata } from "next";
import Link from "next/link";
import { PageIntro } from "@/components/page-intro";

export const metadata: Metadata = { title: "History" };
export default function HistoryPage() {
  return <><PageIntro eyebrow="Activity" title="Scan history" description="Review durable jobs in newest-first order." action={<Link className="button primary" href="/scans/new">New scan</Link>} /><section className="card empty-state"><span className="radar" aria-hidden="true">↺</span><h2>No scan history yet</h2><p>Completed and in-progress scans will be listed here.</p></section></>;
}
