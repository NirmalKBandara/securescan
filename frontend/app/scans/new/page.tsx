import type { Metadata } from "next";
import { PageIntro } from "@/components/page-intro";
import { ScanForm } from "@/components/scan-form";

export const metadata: Metadata = { title: "New scan" };
export default function NewScanPage() {
  return <>
    <PageIntro eyebrow="New scan" title="Define an authorized target" description="Choose a permitted target and port range. SecureScan validates your request before creating the job." />
    <ScanForm />
  </>;
}
