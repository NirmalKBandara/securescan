import Link from "next/link";
import { getSession } from "@/lib/auth/session";

const links = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/scans/new", label: "New scan" },
  { href: "/history", label: "History" },
  { href: "/admin", label: "Admin" },
];

function initials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2)
    .map((part) => part[0]?.toUpperCase()).join("") || "ME";
}

export async function SiteHeader() {
  const session = await getSession();
  return (
    <header className="site-header">
      <div className="nav-wrap">
        <Link className="brand" href="/dashboard" aria-label="SecureScan dashboard">
          <span className="brand-mark" aria-hidden="true">S</span>
          <span>SecureScan</span>
        </Link>
        <nav aria-label="Main navigation">
          <ul className="nav-links">
            {links.map((link) => <li key={link.href}><Link href={link.href}>{link.label}</Link></li>)}
          </ul>
        </nav>
        {session ? <div className="account-controls">
          <span className="avatar" title={session.name} aria-label={`Signed in as ${session.name}`}>
            {initials(session.name)}
          </span>
          <form action="/auth/logout" method="post">
            <button className="logout-button" type="submit">Sign out</button>
          </form>
        </div> : <Link className="avatar" href="/login" aria-label="Account and sign in">?</Link>}
      </div>
    </header>
  );
}
