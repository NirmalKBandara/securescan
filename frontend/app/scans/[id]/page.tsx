import type { Metadata } from "next";
import Link from "next/link";
import { PageIntro } from "@/components/page-intro";

export const metadata: Metadata = { title: "Scan details" };
export default async function ScanDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <><PageIntro eyebrow="Scan details" title="Scan status and findings" description="This page is ready for polling and result rendering in the next frontend sessions." action={<Link className="button secondary" href="/history">Back to history</Link>} /><section className="card detail-list"><h2>Request</h2><dl><div><dt>Scan ID</dt><dd><code>{id}</code></dd></div><div><dt>Status</dt><dd><span className="pill">Awaiting API data</span></dd></div></dl></section></>;
}
