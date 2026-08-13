import type { Metadata } from "next";
import Link from "next/link";
import { PageIntro } from "@/components/page-intro";
import { ScanHistory } from "@/components/scan-history";

export const metadata: Metadata = { title: "History" };
export default function HistoryPage() {
  return (
    <>
      <PageIntro
        eyebrow="Activity"
        title="Scan history"
        description="Review durable jobs in newest-first order. Times are shown in UTC."
        action={<Link className="button primary" href="/scans/new">New scan</Link>}
      />
      <ScanHistory />
    </>
  );
}
