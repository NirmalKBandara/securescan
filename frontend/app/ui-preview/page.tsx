import type { Metadata } from "next";
import { ErrorMessage } from "@/components/error-message";
import { LoadingState } from "@/components/loading-state";
import { PageIntro } from "@/components/page-intro";
import { ResultsTable } from "@/components/results-table";
import { ScanForm } from "@/components/scan-form";
import { ScanStatus } from "@/components/scan-status";
import { mockResults, mockScans } from "@/lib/mocks/scans";

export const metadata: Metadata = { title: "UI preview" };

export default function UiPreviewPage() {
  return <>
    <PageIntro eyebrow="Day 17 preview" title="Reusable scan interface states" description="Mock data exercises every component before the API is connected." />
    <div className="preview-stack">
      <section aria-labelledby="status-preview-title"><h2 id="status-preview-title" className="preview-title">Scan lifecycle states</h2><div className="status-grid">{mockScans.map((scan) => <ScanStatus key={scan.id} scan={scan} />)}</div></section>
      <section aria-labelledby="feedback-preview-title"><h2 id="feedback-preview-title" className="preview-title">Loading and error feedback</h2><div className="feedback-grid"><LoadingState /><ErrorMessage title="Scanner unavailable" message="The scanner service could not be reached. Try again shortly." requestId="req_day17_preview" /></div></section>
      <section aria-labelledby="results-preview-title"><h2 id="results-preview-title" className="preview-title">Populated and empty findings</h2><div className="results-preview"><ResultsTable results={mockResults} /><ResultsTable results={[]} /></div></section>
      <section aria-labelledby="form-preview-title"><h2 id="form-preview-title" className="preview-title">Scan form</h2><ScanForm disabled values={{ target: "scanme.example.com", startPort: 1, endPort: 443, authorized: true }} /></section>
    </div>
  </>;
}
