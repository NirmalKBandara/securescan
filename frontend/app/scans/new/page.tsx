import type { Metadata } from "next";
import { PageIntro } from "@/components/page-intro";

export const metadata: Metadata = { title: "New scan" };
export default function NewScanPage() {
  return <>
    <PageIntro eyebrow="New scan" title="Define an authorized target" description="The interactive submission form and validation arrive on Day 18. This route establishes its accessible layout." />
    <section className="card form-card"><h2>Scan details</h2><div className="field"><label htmlFor="target">Target hostname or IP address</label><input id="target" disabled placeholder="scanme.example.com" /><small>Only public targets on the configured allowlist are accepted.</small></div><div className="port-grid"><div className="field"><label htmlFor="start-port">Start port</label><input id="start-port" disabled value="1" readOnly /></div><div className="field"><label htmlFor="end-port">End port</label><input id="end-port" disabled value="100" readOnly /></div></div><label className="checkbox"><input type="checkbox" disabled /> I confirm that I am authorized to scan this target.</label><button className="button primary" disabled>Submit scan</button><p className="notice" role="note">Preview only — API submission will be connected on Day 18.</p></section>
  </>;
}
