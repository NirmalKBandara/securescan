import type { Metadata } from "next";
import Link from "next/link";
import { PageIntro } from "@/components/page-intro";
import { ScanDetailView } from "@/components/scan-detail";

export const metadata: Metadata = { title: "Scan details" };
export default async function ScanDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <><PageIntro eyebrow="Scan details" title="Scan status and findings" description="Live status and port findings for your authorized scan." action={<Link className="button secondary" href="/history">Back to history</Link>} /><ScanDetailView id={id} /></>;
}
