import type { Metadata } from "next";

export const metadata: Metadata = { title: "Access denied" };

export default function ForbiddenPage() {
  return <section className="auth-card" aria-labelledby="forbidden-title">
    <div className="error-icon access-denied-icon" aria-hidden="true">!</div>
    <p className="eyebrow">Access denied</p>
    <h1 id="forbidden-title">This workspace is restricted</h1>
    <p>Your identity is valid, but it does not have the SecureScan role required for this page.</p>
    <form action="/auth/logout" method="post">
      <button className="button secondary wide" type="submit">Sign out and use another account</button>
    </form>
  </section>;
}
