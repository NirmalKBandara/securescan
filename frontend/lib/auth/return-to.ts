const DEFAULT_DESTINATION = "/dashboard";

export function safeReturnTo(value: string | null | undefined) {
  if (!value || value.length > 2048 || !value.startsWith("/") || value.startsWith("//")) {
    return DEFAULT_DESTINATION;
  }

  try {
    const parsed = new URL(value, "https://securescan.invalid");
    if (parsed.origin !== "https://securescan.invalid" || parsed.pathname.startsWith("/auth/")) {
      return DEFAULT_DESTINATION;
    }
    return `${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    return DEFAULT_DESTINATION;
  }
}

export function isAdminReturnTo(returnTo: string) {
  try {
    const parsed = new URL(returnTo, "https://securescan.invalid");
    if (parsed.origin !== "https://securescan.invalid") return false;
    const pathname = parsed.pathname;
    return pathname === "/admin" || pathname.startsWith("/admin/");
  } catch {
    return false;
  }
}
