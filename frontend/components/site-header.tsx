import Link from "next/link";

const links = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/scans/new", label: "New scan" },
  { href: "/history", label: "History" },
  { href: "/admin", label: "Admin" },
];

export function SiteHeader() {
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
        <Link className="avatar" href="/login" aria-label="Account and sign in">NB</Link>
      </div>
    </header>
  );
}
