import type { Metadata } from "next";
import { PageIntro } from "@/components/page-intro";
import { AdminDashboard } from "@/components/admin-dashboard";
import { APP_ROLES, hasRole } from "@/lib/auth/authorization";
import { getSession } from "@/lib/auth/session";
import { redirect } from "next/navigation";

export const metadata: Metadata = { title: "Administration" };
export default async function AdminPage() {
  const session = await getSession();
  if (!session) redirect("/login?returnTo=/admin");
  if (!hasRole(session, APP_ROLES.admin)) redirect("/forbidden");
  return <><PageIntro eyebrow="Administration" title="Platform controls" description="Monitor every scan, investigate denied activity, and maintain the global target policy." /><AdminDashboard /></>;
}
