import type { Metadata } from "next";
import Link from "next/link";
import { PageIntro } from "@/components/page-intro";
import { ResultsTable } from "@/components/results-table";
import { ScanStatus } from "@/components/scan-status";
import { mockResults, mockScans } from "@/lib/mocks/scans";

export const metadata: Metadata = { title: "Scan details" };
export default async function ScanDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const mockScan = { ...mockScans[2], id };
  return <><PageIntro eyebrow="Scan details" title="Scan status and findings" description="Mock findings demonstrate the reusable Day 17 components before polling is connected." action={<Link className="button secondary" href="/history">Back to history</Link>} /><div className="detail-stack"><ScanStatus scan={mockScan} /><ResultsTable results={mockResults} /></div></>;
}
