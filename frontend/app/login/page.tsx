import type { Metadata } from "next";
import Link from "next/link";
import { env } from "@/lib/env";

export const metadata: Metadata = { title: "Sign in" };
export default function LoginPage() {
  return <section className="auth-card" aria-labelledby="login-title">
    <div className="brand-mark large" aria-hidden="true">S</div>
    <p className="eyebrow">Protected workspace</p>
    <h1 id="login-title">Welcome to SecureScan</h1>
    <p>Sign in through the identity provider to manage authorized network scans.</p>
    <Link className="button primary wide" href={env.loginUrl}>Continue to sign in</Link>
    <p className="fine-print">Only scan systems you own or have explicit permission to test.</p>
  </section>;
}
