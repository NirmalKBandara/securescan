import type { Metadata } from "next";
import Link from "next/link";
import { safeReturnTo } from "@/lib/auth/return-to";

const errors: Record<string, string> = {
  authentication_failed: "Sign-in could not be completed. Please try again.",
  identity_unavailable: "The identity provider is currently unavailable.",
  invalid_transaction: "The sign-in request expired. Please start again.",
};

export const metadata: Metadata = { title: "Sign in" };
export default async function LoginPage({ searchParams }: {
  searchParams: Promise<{ error?: string; returnTo?: string }>;
}) {
  const { error, returnTo } = await searchParams;
  const loginUrl = `/auth/login?${new URLSearchParams({ returnTo: safeReturnTo(returnTo) })}`;
  return <section className="auth-card" aria-labelledby="login-title">
    <div className="brand-mark large" aria-hidden="true">S</div>
    <p className="eyebrow">Protected workspace</p>
    <h1 id="login-title">Welcome to SecureScan</h1>
    <p>Sign in through the identity provider to manage authorized network scans.</p>
    {error && errors[error] ? <p className="auth-error" role="alert">{errors[error]}</p> : null}
    <Link className="button primary wide" href={loginUrl} prefetch={false}>Continue to sign in</Link>
    <p className="fine-print">Only scan systems you own or have explicit permission to test.</p>
  </section>;
}
