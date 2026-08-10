import type { Metadata } from "next";
import { PageIntro } from "@/components/page-intro";
import { ScanForm } from "@/components/scan-form";

export const metadata: Metadata = { title: "New scan" };
export default function NewScanPage() {
  return <>
    <PageIntro eyebrow="New scan" title="Define an authorized target" description="Review the accessible scan controls before submission and validation are connected on Day 18." />
    <ScanForm disabled />
  </>;
}
