import Link from "next/link";
export default function NotFound() { return <section className="auth-card"><p className="eyebrow">404</p><h1>Page not found</h1><p>The page may have moved or the address may be incorrect.</p><Link className="button primary" href="/dashboard">Return to dashboard</Link></section>; }
