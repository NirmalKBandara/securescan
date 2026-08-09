import type { Metadata } from "next";
import { SiteHeader } from "@/components/site-header";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "SecureScan", template: "%s | SecureScan" },
  description: "Submit and review controlled, authorized network scans.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en"><body>
      <a className="skip-link" href="#main-content">Skip to main content</a>
      <SiteHeader />
      <main id="main-content" className="page-shell" tabIndex={-1}>{children}</main>
      <footer><span>SecureScan</span><span>Authorized security testing only</span></footer>
    </body></html>
  );
}
